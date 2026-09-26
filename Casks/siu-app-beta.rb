cask "siu-app-beta" do
  version "1.4.0-beta.4"
  sha256 "ea695ccc88407a4d8f05c1e30c9d7ae92b5979fa11b004a23f242b3238b1a5f1"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Football game across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
