class SiuBeta < Formula
  desc "Play an experimental two-Mac football match across adjacent screens"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  url "https://github.com/ddingddong9/homebrew-siu/releases/download/v1.3.0-beta.2/siu-v1.3.0-beta.2-macos-universal.zip"
  sha256 "62b8926fe7df9f5d1599a283b9ee23723b82b7f71ea17c0298cd139355e038d4"
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
