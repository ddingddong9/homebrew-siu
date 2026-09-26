cask "siu-app-beta" do
  version "1.4.0-beta.3"
  sha256 "6736a9ad8b2d7adf3e34ac2a200acd854e3bb1d10a6dc648415685c223ca9d9f"

  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v#{version}/siu-v#{version}-macos-app.zip"
  name "SIU"
  desc "Football game across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"

  depends_on macos: :ventura

  app "SIU.app"
end
