class SiuBeta < Formula
  desc "Play an experimental two-Mac football match across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v1.3.0-beta.3/siu-v1.3.0-beta.3-macos-universal.zip"
  sha256 "cf2a6b67fe7a0230675ef33c2a116cbb30ebf19e99bc8b7850e79193b0ef1a78"
  license "MIT"

  depends_on macos: :ventura
  conflicts_with "siu", because: "both install the siu executable"

  def install
    bin.install "siu"
    bin.install "siu_MacArrow.bundle"
  end

  test do
    assert_match "kick a football", shell_output("#{bin}/siu --help")
    assert_match "44 transparent character frames OK", shell_output("#{bin}/siu asset-check")
    assert_match "self-test OK", shell_output("#{bin}/siu self-test")
  end
end
