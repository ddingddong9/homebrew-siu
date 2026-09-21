class Siu < Formula
  desc "Kick a football from one Mac into another Mac's screen"
  homepage "https://github.com/ddingddong9/homebrew-siu"
  head "https://github.com/ddingddong9/homebrew-siu.git", branch: "main"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/siu"
  end

  test do
    assert_match "kick a football", shell_output("#{bin}/siu --help")
  end
end
