class Ytmusic < Formula
  desc "Tiny native YouTube Music wrapper for macOS, built from source"
  homepage "https://github.com/caboose-ai/homebrew-ytmusic"
  url "https://github.com/caboose-ai/homebrew-ytmusic/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "3c6b21f4202360b2ed5da5c79422309b1525b3248a1132fc341400f988db003b"
  license "MIT"
  head "https://github.com/caboose-ai/homebrew-ytmusic.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "bash", "scripts/build-app.sh", "dist"
    prefix.install "dist/YTMusic.app"
  end

  def caveats
    <<~EOS
      To make YT Music show up in Spotlight and Launchpad, link it into /Applications:
        ln -sf #{opt_prefix}/YTMusic.app /Applications/YTMusic.app
    EOS
  end

  test do
    assert_predicate prefix/"YTMusic.app/Contents/MacOS/YTMusic", :executable?
    system "plutil", "-lint", prefix/"YTMusic.app/Contents/Info.plist"
  end
end
