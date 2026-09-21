class Siu < Formula
  desc "Kick a football from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  on_arm do
    url "https://github.com/ddingddong9/homebrew-siu/releases/download/v1.2.0/siu-v1.2.0-macos-arm64.zip"
    sha256 "52a6634dbebec20fb12f92665350b29c3b7856e5a249dd6f8924a0a131544e9b"
  end

  on_intel do
    odie "siu currently provides a prebuilt Apple Silicon package only."
  end

  license "MIT"

  def install
    bin.install "bin/siu"
    bin.install "bin/siu_MacArrow.bundle"
  end

  test do
    assert_match "kick a football", shell_output("#{bin}/siu --help")
    assert_match "character asset OK", shell_output("#{bin}/siu asset-check")
  end
end
