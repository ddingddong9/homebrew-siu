cask "siu-app-beta" do
  version "1.11.0-beta.1"
  sha256 "d1301ecfef15891f42338fe59b49db5c0119949a290d4ba0a12d30f9acf4d5f5"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
