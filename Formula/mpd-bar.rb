class MpdBar < Formula
  desc "Menu bar remote for MPD and Mopidy web radio playlists"
  homepage "https://github.com/ts-sz/mpd-bar"
  url "https://github.com/ts-sz/mpd-bar/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "6cdca69ccc5a0cdf6b235513b421cb5f4656e0cfbd9d07e0892914a21ded192d"
  license "MIT"
  head "https://github.com/ts-sz/mpd-bar.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "MPDBar"
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "mpdbar-probe"
    build_bin = Pathname(Utils.safe_popen_read("swift", "build", "--disable-sandbox", "-c", "release",
                                               "--show-bin-path").strip)

    app = prefix/"MPDBar.app"
    (app/"Contents/MacOS").mkpath
    cp build_bin/"MPDBar", app/"Contents/MacOS/MPDBar"
    cp "Resources/Info.plist", app/"Contents/Info.plist"
    system "codesign", "--force", "-s", "-", app

    bin.install build_bin/"mpdbar-probe"
    (bin/"mpd-bar").write <<~SH
      #!/bin/bash
      exec open "#{opt_prefix}/MPDBar.app"
    SH
    chmod 0755, bin/"mpd-bar"
  end

  service do
    run [opt_prefix/"MPDBar.app/Contents/MacOS/MPDBar"]
    run_type :immediate
    keep_alive false
  end

  def caveats
    <<~EOS
      Start MPD Bar now and at every login:
        brew services start mpd-bar
      Or open it once:
        mpd-bar
      The radio icon appears in the menu bar. Click it, then fill in Settings.
    EOS
  end

  test do
    assert_predicate prefix/"MPDBar.app/Contents/MacOS/MPDBar", :executable?
    assert_match "usage", shell_output("#{bin}/mpdbar-probe 2>&1", 2)
  end
end
