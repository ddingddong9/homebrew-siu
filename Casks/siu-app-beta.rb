cask "siu-app-beta" do
  version "1.11.0-beta.2"
  sha256 "a29946ee24df05907b9b906958498193cc04fae0b56b9dce83d12425a2f13093"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
