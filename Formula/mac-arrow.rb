class MacArrow < Formula
  desc "Shoot an animated arrow from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-mac-arrow"
  url "https://github.com/ddingddong9/homebrew-mac-arrow/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "8c132b33dd025b5e9fa6714f43e3e993613c94b69683c2c51585503ccf5d46b0"
  head "https://github.com/ddingddong9/homebrew-mac-arrow.git", branch: "main"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/mac-arrow"
  end

  test do
    assert_match "send an arrow", shell_output("#{bin}/mac-arrow --help")
  end
end
