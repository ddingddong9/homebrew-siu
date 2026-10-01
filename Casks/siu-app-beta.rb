cask "siu-app-beta" do
  version "1.14.0-beta.1"
  sha256 "012d7b6f64beadfa2f7a6067afb0089959ddb9e35925571f844610b69d0455bb"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one and four-player two-a-side LAN football"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
