cask "siu-app-beta" do
  version "1.9.0-beta.1"
  sha256 "2aabbdc370513d7b68bb1ae6011130ed57da6b290bd75fcac11054b14559f332"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
