class Powersaver < Formula
  desc "Lightweight event-driven macOS menu bar app to suspend idle apps on battery"
  homepage "https://github.com/Rafli161102/powersaver-mac"
  head "https://github.com/Rafli161102/powersaver-mac.git", branch: "main"
  license "MIT"

  depends_on :macos

  def install
    app_dir = prefix/"PowerSaver.app"
    macos_dir = app_dir/"Contents/MacOS"
    scripts_dir = app_dir/"Contents/Resources/scripts"

    macos_dir.mkpath
    scripts_dir.mkpath

    cp "resources/Info.plist", app_dir/"Contents/Info.plist"
    cp Dir["scripts/*.sh"], scripts_dir
    chmod 0755, Dir[scripts_dir/"*.sh"]

    system "swiftc", "-swift-version", "5", "-O",
           "-framework", "Cocoa", "-framework", "IOKit",
           "src/PowerSaverApp.swift",
           "-o", macos_dir/"PowerSaver"

    system "codesign", "--force", "--sign", "-", app_dir

    (bin/"powersaver").write <<~EOS
      #!/bin/zsh
      exec open -a "#{opt_prefix}/PowerSaver.app" "$@"
    EOS
    chmod 0755, bin/"powersaver"
  end

  def caveats
    <<~EOS
      PowerSaver.app has been built at:
        #{opt_prefix}/PowerSaver.app

      To launch PowerSaver immediately:
        powersaver

      To install the LaunchAgent and copy PowerSaver.app into ~/Applications:
        mkdir -p ~/Applications ~/Library/LaunchAgents
        cp -R "#{opt_prefix}/PowerSaver.app" ~/Applications/
        sed "s|__APP_EXECUTABLE__|${HOME}/Applications/PowerSaver.app/Contents/MacOS/PowerSaver|g" \
          "#{pkgshare}/com.rafli.powersaver.plist.template" 2>/dev/null || true
    EOS
  end
end
