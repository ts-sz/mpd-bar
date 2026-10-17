class MpdBar < Formula
  desc "Menu bar remote for MPD and Mopidy web radio playlists"
  homepage "https://github.com/ts-sz/mpd-bar"
  url "https://github.com/ts-sz/mpd-bar/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "fdb85bbb053447d314143948890b1ef1cab965d2d7d0c623207429186d1a1150"
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
      Create the config file, edit it, then check it:
        mpdbar-probe init
        open -t ~/.config/mpd-bar/config.json
        mpdbar-probe playlists
        mpdbar-probe use NAME
      The app reloads the file on save. Format: https://github.com/ts-sz/mpd-bar#config-file
    EOS
  end

  test do
    assert_predicate prefix/"MPDBar.app/Contents/MacOS/MPDBar", :executable?
    assert_match "usage", shell_output("#{bin}/mpdbar-probe --help")
    ENV["MPDBAR_CONFIG"] = (testpath/"config.json").to_s
    assert_match "Wrote", shell_output("#{bin}/mpdbar-probe init")
    assert_equal "600", format("%o", (testpath/"config.json").stat.mode & 0777)
  end
end
