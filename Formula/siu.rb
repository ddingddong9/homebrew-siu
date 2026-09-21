class Siu < Formula
  desc "Kick a football from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  url "https://github.com/ddingddong9/homebrew-siu/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "70dd093eeff8e78f7a24a1a27780143c888d07f5cf007899777f665805d434d2"
  head "https://github.com/ddingddong9/homebrew-siu.git", branch: "main"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/siu"
    bin.install ".build/release/siu_MacArrow.bundle"
  end

  test do
    assert_match "kick a football", shell_output("#{bin}/siu --help")
    assert_match "character asset OK", shell_output("#{bin}/siu asset-check")
  end
end
