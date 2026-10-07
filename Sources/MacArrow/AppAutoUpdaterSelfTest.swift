import Foundation

enum AppAutoUpdaterSelfTest {
    static func run() -> [String] {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("siu-updater-test-"+UUID().uuidString)
        defer { try? fm.removeItem(at:folder) }
        do {
            try fm.createDirectory(at:folder,withIntermediateDirectories:false)
            let target = folder.appendingPathComponent("SIU.app")
            let incoming = folder.appendingPathComponent(".SIU-incoming-test.app")
            let backup = folder.appendingPathComponent(".SIU-backup-test.app")
            func makeApp(_ path:URL,_ version:String) throws {
                try fm.createDirectory(at:path.appendingPathComponent("Contents/MacOS"),withIntermediateDirectories:true)
                let info: [String:Any] = ["CFBundleIdentifier":"com.ddingddong9.siu","CFBundleExecutable":"siu","CFBundlePackageType":"APPL","CFBundleVersion":"1","SIUReleaseVersion":version]
                try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:path.appendingPathComponent("Contents/Info.plist"))
                try fm.copyItem(at:URL(fileURLWithPath:CommandLine.arguments[0]),to:path.appendingPathComponent("Contents/MacOS/siu"))
                try AppAutoUpdater.run("/usr/bin/codesign",["--force","--deep","--sign","-",path.path])
            }
            try makeApp(target,"0.0.0-beta.1"); try makeApp(incoming,"0.0.0-beta.2")
            let invalid = AppAutoUpdater.Plan(parentPID:getpid(),target:target.path,incoming:incoming.path,backup:backup.path,version:"0.0.0-beta.3")
            do { try AppAutoUpdater.replace(invalid); return ["updater accepted wrong version"] } catch { }
            guard fm.fileExists(atPath:target.path),!fm.fileExists(atPath:backup.path) else { return ["updater invalid version changed existing app"] }
            let plan = AppAutoUpdater.Plan(parentPID:getpid(),target:target.path,incoming:incoming.path,backup:backup.path,version:"0.0.0-beta.2")
            try AppAutoUpdater.replace(plan)
            try AppAutoUpdater.validateApp(target,version:"0.0.0-beta.2")
            try AppAutoUpdater.validateApp(backup,version:"0.0.0-beta.1")
            try fm.createSymbolicLink(at:target.appendingPathComponent("Contents/escape"),withDestinationURL:folder.deletingLastPathComponent())
            do { try AppAutoUpdater.validateApp(target,version:"0.0.0-beta.2"); return ["updater accepted escaping symlink"] } catch { }
            return []
        } catch { return ["updater installation regression: \(error.localizedDescription)"] }
    }
}
