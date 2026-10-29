class Ytmusic < Formula
  desc "Tiny native YouTube Music wrapper for macOS, built from source"
  homepage "https://github.com/caboose-ai/homebrew-ytmusic"
  url "https://github.com/caboose-ai/homebrew-ytmusic/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "12c9ab09e699fbf3b3cc5814f081801f386faacd2c7f54a0b08eeaf691b6bb97"
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
