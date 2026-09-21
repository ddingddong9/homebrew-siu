class Siu < Formula
  desc "Kick a football from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  url "https://github.com/ddingddong9/homebrew-siu/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "52f5b25d9ecf67321a30092f86d20918cc25e61d43e39c09466a17c41aa8d0e2"
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
