cask "siu-app-beta" do
  version "1.10.0-beta.1"
  sha256 "d3ba8b2dfb84b8eed55450595f6771f0dbb45e4284e1c383743abc346fdc9b43"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
