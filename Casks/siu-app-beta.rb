cask "siu-app-beta" do
  version "1.4.0-beta.5"
  sha256 "bb82b6dbb9ada05ec278440d75f5f547b3b5c52c421377c03f2a73155f8c65ef"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Football game across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
