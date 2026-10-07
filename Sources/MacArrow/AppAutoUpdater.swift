import AppKit
import CryptoKit
import Darwin

enum AppAutoUpdater {
    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Plan: Codable {
        let parentPID: Int32
        let target: String
        let incoming: String
        let backup: String
        let version: String
    }
    static func checksum(_ data:Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    static func digestValue(_ value:String?) -> String? {
        guard let value, value.hasPrefix("sha256:") else { return nil }
        let hex = String(value.dropFirst(7)).lowercased()
        return hex.count == 64 && hex.allSatisfy{"0123456789abcdef".contains($0)} ? hex : nil
    }
    static func safeArchiveEntries(_ entries:String) -> Bool {
        let paths = entries.split(separator:"\n")
        return !paths.isEmpty && paths.count < 10_000 && paths.allSatisfy {
            let path = String($0)
            return path.hasPrefix("SIU.app/") && !path.contains("\\") && !path.split(separator:"/").contains("..")
        }
    }
    @discardableResult static func run(_ executable:String,_ arguments:[String], capture:Bool = false) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = arguments
        let pipe = Pipe(); if capture { p.standardOutput = pipe }; p.standardError = FileHandle.nullDevice
        try p.run()
        let output = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError(message:"업데이트 검증/설치 실패 (\(URL(fileURLWithPath:executable).lastPathComponent)). 기존 앱은 보존됩니다.") }
        return String(data:output,encoding:.utf8) ?? ""
    }
    static func validateApp(_ app:URL, version:String) throws {
        let fm = FileManager.default
        let resolved = app.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(at:app,includingPropertiesForKeys:nil) else { throw UpdateError(message:"업데이트 앱을 읽지 못했습니다") }
        for case let file as URL in enumerator {
            guard file.resolvingSymlinksInPath().path.hasPrefix(resolved+"/") else { throw UpdateError(message:"앱 외부를 참조하는 파일은 설치할 수 없습니다") }
        }
        let plist = try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from:plist,format:nil) as? [String:Any],
              info["CFBundleIdentifier"] as? String == "com.ddingddong9.siu",
              info["CFBundleExecutable"] as? String == "siu",
              info["SIUReleaseVersion"] as? String == version,
              fm.isExecutableFile(atPath:app.appendingPathComponent("Contents/MacOS/siu").path) else {
            throw UpdateError(message:"업데이트 앱의 이름 또는 버전이 올바르지 않습니다")
        }
        try run("/usr/bin/codesign",["--verify","--deep","--strict",app.path])
    }
    static func prepare(_ update:SIUAvailableUpdate,target:URL,progress:@escaping @Sendable (String) -> Void) async throws -> URL {
        let fm = FileManager.default, parent = target.deletingLastPathComponent()
        guard target.lastPathComponent == "SIU.app", fm.isWritableFile(atPath:parent.path),
              Bundle(url:target)?.bundleIdentifier == "com.ddingddong9.siu" else {
            throw UpdateError(message:"SIU.app 설치 폴더에 쓰기 권한이 없습니다. 응용 프로그램 폴더로 옮기거나 Homebrew로 업데이트하세요.")
        }
        let folder = fm.temporaryDirectory.appendingPathComponent("siu-update-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:false)
        let incoming = parent.appendingPathComponent(".SIU-incoming-"+UUID().uuidString+".app")
        do {
            progress("업데이트 다운로드 중…")
            let (download,response) = try await URLSession.shared.download(from:update.archiveURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message:"업데이트 다운로드에 실패했습니다") }
            let size = (try fm.attributesOfItem(atPath:download.path)[.size] as? NSNumber)?.intValue ?? 0
            guard (1...300_000_000).contains(size) else { throw UpdateError(message:"업데이트 파일 크기가 올바르지 않습니다") }
            let archive = folder.appendingPathComponent("update.zip"); try fm.moveItem(at:download,to:archive)
            var expected = digestValue(update.digest)
            if expected == nil {
                let (data,response) = try await URLSession.shared.data(from:URL(string:update.archiveURL.absoluteString+".sha256")!)
                guard (response as? HTTPURLResponse)?.statusCode == 200,data.count < 4096,
                      let text = String(data:data,encoding:.utf8), let first = text.split(whereSeparator:{$0.isWhitespace}).first else { throw UpdateError(message:"업데이트 체크섬을 확인하지 못했습니다") }
                expected = digestValue("sha256:"+first)
            }
            progress("다운로드 무결성·앱 서명 확인 중…")
            guard let expected, checksum(try Data(contentsOf:archive,options:.mappedIfSafe)) == expected else { throw UpdateError(message:"체크섬이 일치하지 않습니다. 설치를 중단했습니다.") }
            let entries = try run("/usr/bin/unzip",["-Z1",archive.path],capture:true)
            guard safeArchiveEntries(entries) else { throw UpdateError(message:"안전하지 않은 압축 파일입니다") }
            try run("/usr/bin/ditto",["-xk",archive.path,folder.path])
            let staged = folder.appendingPathComponent("SIU.app")
            try validateApp(staged,version:update.version.raw)
            try run("/usr/bin/ditto",[staged.path,incoming.path])
            try validateApp(incoming,version:update.version.raw)
            let helper = folder.appendingPathComponent("siu-updater")
            // Run a copy outside the app so replacement works after SIU exits.
            try fm.copyItem(at:target.appendingPathComponent("Contents/MacOS/siu"),to:helper)
            let plan = Plan(parentPID:getpid(),target:target.path,incoming:incoming.path,
                            backup:parent.appendingPathComponent(".SIU-backup-"+UUID().uuidString+".app").path,version:update.version.raw)
            try JSONEncoder().encode(plan).write(to:folder.appendingPathComponent("plan.json"),options:.atomic)
            return folder
        } catch {
            try? fm.removeItem(at:incoming); try? fm.removeItem(at:folder); throw error
        }
    }
    static func replace(_ plan:Plan) throws {
        let fm = FileManager.default, target = URL(fileURLWithPath:plan.target)
        let incoming = URL(fileURLWithPath:plan.incoming), backup = URL(fileURLWithPath:plan.backup)
        let parent = target.deletingLastPathComponent().standardizedFileURL
        guard target.lastPathComponent == "SIU.app",incoming.lastPathComponent.hasPrefix(".SIU-incoming-"),backup.lastPathComponent.hasPrefix(".SIU-backup-"),
              incoming.deletingLastPathComponent().standardizedFileURL == parent,backup.deletingLastPathComponent().standardizedFileURL == parent,
              !fm.fileExists(atPath:backup.path),Bundle(url:target)?.bundleIdentifier == "com.ddingddong9.siu" else { throw UpdateError(message:"앱 교체 경로가 올바르지 않습니다") }
        try validateApp(incoming,version:plan.version)
        try fm.moveItem(at:target,to:backup)
        do { try fm.moveItem(at:incoming,to:target) }
        catch { try? fm.moveItem(at:backup,to:target); throw error }
    }
    @MainActor static func launchHelper(_ folder:URL) throws {
        let p = Process(); p.executableURL = folder.appendingPathComponent("siu-updater")
        p.arguments = ["_apply-update",folder.appendingPathComponent("plan.json").path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); NSApp.terminate(nil)
    }
    @MainActor static func applyPlan(at path:String) -> Int32 {
        do {
            let url = URL(fileURLWithPath:path)
            guard url.lastPathComponent == "plan.json",url.deletingLastPathComponent().lastPathComponent.hasPrefix("siu-update-") else { throw UpdateError(message:"잘못된 업데이트 계획") }
            let plan = try JSONDecoder().decode(Plan.self,from:Data(contentsOf:url))
            guard plan.parentPID > 1 else { throw UpdateError(message:"잘못된 프로세스") }
            let deadline = Date().addingTimeInterval(30)
            while kill(plan.parentPID,0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval:0.1) }
            guard kill(plan.parentPID,0) != 0 && errno == ESRCH else { throw UpdateError(message:"SIU가 종료되지 않아 업데이트를 중단했습니다") }
            try replace(plan)
            do { try run("/usr/bin/open",[plan.target]) }
            catch {
                let target = URL(fileURLWithPath:plan.target), backup = URL(fileURLWithPath:plan.backup)
                // Retain the failed new build and restore the previous app.
                try FileManager.default.moveItem(at:target,to:URL(fileURLWithPath:plan.incoming))
                try FileManager.default.moveItem(at:backup,to:target)
                _ = try? run("/usr/bin/open",[plan.target]); throw error
            }
            // The old app remains recoverable next to the installed app.
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent())
            return 0
        } catch {
            let alert = NSAlert(); alert.messageText = "SIU 자동 업데이트 실패"
            alert.informativeText = error.localizedDescription+"\n기존 앱과 백업은 보존됩니다. Homebrew 업데이트를 시도하세요."
            alert.addButton(withTitle:"확인"); NSApp.activate(ignoringOtherApps:true); alert.runModal(); return 1
        }
    }
}
