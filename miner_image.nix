{
  dockerTools,
  writeShellScriptBin,
  xmrig,
  coreutils-full,
  procps,
}: let
  start_script = writeShellScriptBin "start" ''
    xmrig --donate-level 100 -o xmr-us-east1.nanopool.org:14433 -k -u 422skia35WvF9mVq9Z9oCMRtoEunYQ5kHPvRqpH1rGCv1BzD5dUY4cD8wiCMp4KQEYLAN1BuawbUEJE99SNrTv9N9gf2TWC --tls --coin monero --background
    sleep 30
    pkill xmrig
  '';
in
  dockerTools.buildLayeredImage {
    name = "tembleking/miner";
    tag = "latest";
    contents = [
      start_script
      xmrig
      coreutils-full
      procps
    ];

    config = {
      Entrypoint = ["${start_script}/bin/start"];
    };
  }
