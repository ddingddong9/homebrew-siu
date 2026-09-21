class MacArrow < Formula
  desc "Shoot an animated arrow from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-mac-arrow"
  url "https://github.com/ddingddong9/homebrew-mac-arrow/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "78a19f8955f3ae4953a829b0376c1aa12f537012585f46b6a2c30fd62b9a2378"
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
