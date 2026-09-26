import Foundation

enum ResourceBundle {
    static var images: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("siu_MacArrow.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }
}
