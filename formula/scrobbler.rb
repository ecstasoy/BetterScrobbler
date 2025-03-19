class Scrobbler < Formula
  desc "A global macOS Last.fm Scrobbler with support for various music platforms"
  homepage "https://github.com/ecstasoy/BetterScrobbler"
  url "https://github.com/ecstasoy/BetterScrobbler/releases/download/v1.2.2/scrobbler-1.2.2.tar.gz"
  sha256 "355d19ac637ce226f9dae96628e327d4308c166c90827c4f8672849f50750875"
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
