class Siu < Formula
  desc "Kick a football from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  on_arm do
    url "https://github.com/ddingddong9/homebrew-siu/releases/download/v1.2.1/siu-v1.2.1-macos-arm64.zip"
    sha256 "7aeac4345ad6711f9278bc4065031ee1bea92f097ce4f072b7aef7535cc9461c"
  end

  on_intel do
    odie "siu currently provides a prebuilt Apple Silicon package only."
  end

  license "MIT"

  def install
    bin.install "siu"
    bin.install "siu_MacArrow.bundle"
  end

  test do
    assert_match "kick a football", shell_output("#{bin}/siu --help")
    assert_match "character asset OK", shell_output("#{bin}/siu asset-check")
  end
end
