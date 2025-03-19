class Scrobbler < Formula
  desc "A global macOS Last.fm Scrobbler with support for various music platforms"
  homepage "https://github.com/ecstasoy/BetterScrobbler"
  url "https://github.com/ecstasoy/BetterScrobbler/releases/download/v1.2.2/scrobbler-1.2.2.tar.gz"
  sha256 "e6ed3e262c699316234c19c614a3b188ca151239678832113b8a3b930c469e82"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "curl"
  depends_on :macos

  def install
    rm_r "build" if Dir.exist?("build")

    mkdir "build"
    cd "build" do
      system "cmake", "..", *std_cmake_args
      system "cmake", "--build", "."
    end

    bin.install "build/Scrobbler"
  end

  service do
    run [opt_bin/"Scrobbler"]
    keep_alive true
    log_path var/"log/scrobbler.log"
    error_log_path var/"log/scrobbler.log"
  end

  test do
    system "#{bin}/Scrobbler", "--help"
  end
end
