cask "siu-app-beta" do
  version "1.14.0-beta.2"
  sha256 "c5fc74a421fbae26e2de8abc589ff9cf7937a1e1d7553a29fc6eb6deed756bbe"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one and four-player two-a-side LAN football"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
