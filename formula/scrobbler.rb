class Scrobbler < Formula
  desc "A global macOS Last.fm Scrobbler with support for various music platforms"
  homepage "https://github.com/ecstasoy/BetterScrobbler"
  url "https://github.com/ecstasoy/BetterScrobbler/releases/download/v1.0.0/scrobbler-1.0.0.tar.gz"
  sha256 "55d9ec55242025d85475f7ae093e80b4b939a30303a5aaa4409bfcbbf8338ebd"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "curl"
  depends_on :macos

  def install
    rm_rf "build"

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
