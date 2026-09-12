// A Dagger module that builds a reproducible Guix installation image
// inside a container (x86_64 ISO by default; pass --arch for arm64).
//
// Edit channels.scm to change which Guix commit is used, then run:
//
//	dagger call build export --path=./guix-install-x86_64-linux.iso
//	dagger call build --arch=aarch64 export --path=./guix-install-aarch64-linux.raw

package main

import (
	"context"

	"dagger/guix-iso/internal/dagger"
)

const guixVersion = "1.5.0"

// platformFor maps a Guix system string to the Dagger container platform.
var platformFor = map[string]dagger.Platform{
	"x86_64":  "linux/amd64",
	"aarch64": "linux/arm64",
}

// setupScript runs after the tarball is extracted; it creates the build
// users and authorizes the substitute servers. It has no dependency on
// channels.scm, so Dagger caches it as a layer.
const setupScript = `
set -euo pipefail
groupadd --system guixbuild
for i in $(seq -w 1 10); do
  useradd -g guixbuild -G guixbuild -d /var/empty -s /bin/false \
    -c "Guix build user $i" --system "guixbuilder$i"
done
GUIX=/var/guix/profiles/per-user/root/current-guix/bin/guix
"$GUIX" archive --authorize < /var/guix/profiles/per-user/root/current-guix/share/guix/bordeaux.guix.gnu.org.pub
"$GUIX" archive --authorize < /var/guix/profiles/per-user/root/current-guix/share/guix/ci.guix.gnu.org.pub
`

type GuixIso struct{}

// setup builds a container with Guix installed for the given architecture
// (daemon not started).
func setup(arch string) *dagger.Container {
	tarball := "guix-binary-" + guixVersion + "." + arch + "-linux.tar.xz"
	return dag.Container(dagger.ContainerOpts{Platform: platformFor[arch]}).
		From("debian:stable-slim").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "--no-install-recommends",
			"curl", "ca-certificates", "xz-utils", "gnupg", "passwd", "netbase"}).
		WithExec([]string{"curl", "-fsSL", "-o", "/tmp/" + tarball,
			"https://ftp.gnu.org/gnu/guix/" + tarball}).
		WithExec([]string{"tar", "-C", "/", "--warning=no-timestamp", "-xf", "/tmp/" + tarball}).
		WithExec([]string{"bash", "-c", setupScript})
}

// Build assembles the Guix installation ISO and returns it as a file.
func (m *GuixIso) Build(
	ctx context.Context,
	// Architecture of the ISO: "x86_64" or "aarch64".
	// +optional
	arch string,
) *dagger.File {
	if arch == "" {
		arch = "x86_64"
	}

	// x86_64 produces an ISO (BIOS boot); aarch64 produces a raw EFI image.
	ext := "iso"
	if arch == "aarch64" {
		ext = "raw"
	}

	src := dag.CurrentModule().Source()

	return setup(arch).
		WithMountedDirectory("/workspace", src).
		WithExec([]string{"bash", "/workspace/pull.sh"},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		WithExec([]string{"bash", "/workspace/image.sh", arch},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		File("/out/guix-install-" + arch + "-linux." + ext)
}

// Debug returns the setup container for inspection without running the build.
func (m *GuixIso) Debug(
	// +optional
	arch string,
) *dagger.Container {
	if arch == "" {
		arch = "x86_64"
	}
	return setup(arch)
}
