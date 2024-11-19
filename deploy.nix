{
  writeShellApplication,
  helmfile,
  kubernetes-helm,
}:
writeShellApplication {
  name = "deploy";
  runtimeInputs = [
    helmfile
    kubernetes-helm
  ];
  text = ''
    helmfile sync -f ${./helmfile.yaml}
  '';
}
