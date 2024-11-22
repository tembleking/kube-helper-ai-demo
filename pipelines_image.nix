{
  dockerTools,
  kubectl,
  writeTextDir,
}:
let
  baseImage = dockerTools.pullImage (import ./base_pipelines_image.nix);

  passwd-file = writeTextDir "etc/passwd" ''
    root:x:0:0:root:/root:/bin/bash
    daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
    bin:x:2:2:bin:/bin:/usr/sbin/nologin
    sys:x:3:3:sys:/dev:/usr/sbin/nologin
    sync:x:4:65534:sync:/bin:/bin/sync
    games:x:5:60:games:/usr/games:/usr/sbin/nologin
    man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
    lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
    mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
    news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
    uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
    proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
    www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
    backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
    list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
    irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
    _apt:x:42:65534::/nonexistent:/usr/sbin/nologin
    nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
    john:x:1000:1000::/home/john:/bin/sh
  '';

  shadow-file = writeTextDir "etc/shadow" ''
    root:*:19905:0:99999:7:::
    daemon:*:19905:0:99999:7:::
    bin:*:19905:0:99999:7:::
    sys:*:19905:0:99999:7:::
    sync:*:19905:0:99999:7:::
    games:*:19905:0:99999:7:::
    man:*:19905:0:99999:7:::
    lp:*:19905:0:99999:7:::
    mail:*:19905:0:99999:7:::
    news:*:19905:0:99999:7:::
    uucp:*:19905:0:99999:7:::
    proxy:*:19905:0:99999:7:::
    www-data:*:19905:0:99999:7:::
    backup:*:19905:0:99999:7:::
    list:*:19905:0:99999:7:::
    irc:*:19905:0:99999:7:::
    _apt:*:19905:0:99999:7:::
    nobody:*:19905:0:99999:7:::
    john:$y$j9T$A1ZwuPr73ULjS4qgr.L.u.$qGxS.pat3R0nTk51viDemZAl0NLYHAbJlnULQGRUn04:19916:0:99999:7:::
  '';

  bash-history-file = writeTextDir "root/.bash_history" ''
    which cat
    cat /root/.bashrc
    ls -al
    useradd john
    echo "john:supersecret" | chpasswd
  '';

  image = dockerTools.buildLayeredImage {
    name = "ghcr.io/tembleking/open-webui-pipelines";
    tag = "0.0.2";
    fromImage = baseImage;
    contents = [
      kubectl
      passwd-file
      shadow-file
      bash-history-file
    ];
    config = {
      Entrypoint = [
        "bash"
        "start.sh"
      ];
      WorkingDir = "/app";
    };
    extraCommands = ''
      commandsToLink=(sh ls cat)
      for command in "''${commandsToLink[@]}"; do
        ln -s /usr/bin/"$command" bin/"$command";
      done
    '';
  };
in
image
