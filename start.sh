qemu-system-aarch64 \
  -machine virt \
  -accel hvf -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/Applications/UTM.app/Contents/Resources/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/Linux.utm/Data/efi_vars.fd" \
  -drive if=virtio,format=qcow2,file=/Users/morkswork/Downloads/guix-install-aarch64-linux.qcow2 \
  -drive if=virtio,format=qcow2,file=blank-32g.qcow2 \
  -nic user,model=virtio-net-pci \
  -nographic
