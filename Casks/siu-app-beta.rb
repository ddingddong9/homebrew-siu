cask "siu-app-beta" do
  version "1.16.0-beta.1"
  sha256 "21a65c2503b50602afe4da2309d83fac6cdec817c24799ab221a50eb9ff4308b"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one and four-player two-a-side LAN football"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
