class Ytmusic < Formula
  desc "Tiny native YouTube Music wrapper for macOS, built from source"
  homepage "https://github.com/caboose-ai/homebrew-ytmusic"
  url "https://github.com/caboose-ai/homebrew-ytmusic/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "cdab756aed9282c5ead1ccfa5d0a0737828dd4592b56c4566678d707c83e5e6a"
  license "MIT"
  head "https://github.com/caboose-ai/homebrew-ytmusic.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "bash", "scripts/build-app.sh", "dist"
    prefix.install "dist/YTMusic.app"
  end

  # A real copy, not a symlink: launchers (Raycast, Spotlight) resolve symlinks
  # down to the versioned Cellar folder, which is deleted on every upgrade.
  # Copying into /Applications from a formula is unusual, but this is a personal tap.
  def post_install
    target = Pathname("/Applications/YTMusic.app")
    FileUtils.rm_rf(target)
    FileUtils.cp_r(prefix/"YTMusic.app", target)
  rescue SystemCallError => e
    opoo "Could not copy YTMusic.app into /Applications (#{e.message}). " \
         "Copy it yourself: cp -R #{prefix}/YTMusic.app /Applications/"
  end

  def caveats
    <<~EOS
      YTMusic.app is copied into /Applications on every install and upgrade,
      so Spotlight and Raycast keep working across versions. Quit the app
      before upgrading so the copy can be replaced.
    EOS
  end

  test do
    assert_predicate prefix/"YTMusic.app/Contents/MacOS/YTMusic", :executable?
    system "plutil", "-lint", prefix/"YTMusic.app/Contents/Info.plist"
  end
end
