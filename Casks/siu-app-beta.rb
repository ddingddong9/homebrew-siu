cask "siu-app-beta" do
  version "1.13.0-beta.1"
  sha256 "482e58b4bd66a507865c71e7a077c7effa4cdebfccfddb350dcc80bda607b216"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "One-on-one LAN football with a stadium lobby and animated skills"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
