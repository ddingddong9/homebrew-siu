cask "siu-app-beta" do
  version "1.7.0-beta.2"
  sha256 "9d71deaaa48e3309ba122606824a9dda7a6a1b8875b1d5120a1bbec7e79acb06"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Two-player football game on a shared pitch"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
