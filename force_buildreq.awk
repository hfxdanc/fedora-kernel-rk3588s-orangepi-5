BEGIN {
    delete force

    # Required for RPM to build
    # from Fedora
    force["CONFIG_DEBUG_INFO_BTF"] = "y"
    force["CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT"] = "y"
    force["CONFIG_DEBUG_INFO_NONE"] = "n"
    force["CONFIG_DEBUG_INFO_REDUCED"] = "n"
    force["CONFIG_EFI_ZBOOT"] = "y"
    force["CONFIG_LSM"] = "\"lockdown,yama,integrity,selinux,bpf,landlock\""
    #force["CONFIG_LSM"] = "\"lockdown,yama,integrity,selinux,bpf,landlock,loadpin,safesetid\""
    force["CONFIG_MODULE_SIG_KEY"] = "\"certs/signing_key.pem\""
    force["CONFIG_MODULE_SIG"] = "y"
    force["CONFIG_SECURITY_LOCKDOWN_LSM"] = "y"
}
