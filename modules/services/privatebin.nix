{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # PRIVATEBIN (ENCRYPTED PASTEBIN)
  # ============================================================================

  services.privatebin = {
    enable = true;
    enableNginx = true;
    virtualHost = commonConfig.services.privatebin;

    settings = {
      main = {
        name = "${commonConfig.domain} PrivateBin";
        discussion = true;
        opendiscussion = true;
        fileupload = true;
        burnafterreadingselected = false;
        defaultformatter = "plaintext";
        languageselection = true;
        sizelimit = 10485760;  # 10MB
        template = "bootstrap";
        languagedefault = "de";
      };

      expire = {
        default = "1month";
      };

      expire_options = {
        "5min" = 300;
        "10min" = 600;
        "1hour" = 3600;
        "1day" = 86400;
        "1week" = 604800;
        "1month" = 2592000;
        "1year" = 31536000;
        "never" = 0;
      };

      formatter_options = {
        plaintext = "Plain Text";
        syntaxhighlighting = "Source Code";
        markdown = "Markdown";
      };

      model = {
        class = "Filesystem";
      };

      model_options = {
        dir = "/var/lib/privatebin/data";
      };

      purge = {
        limit = 300;
      };
    };
  };
}
