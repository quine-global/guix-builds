// A Dagger module that builds a reproducible Guix installation image
// inside a native amd64 container, cross-building the target architecture
// with --target (no QEMU emulation).
//
// Edit channels.scm to change which Guix commit is used, then run:
//
//	dagger call build export --path=./out
//	dagger call build --arch=aarch64 export --path=./out

package main

import (
	"context"

	"dagger/guix-iso/internal/dagger"
)

const guixVersion = "1.5.0"

// We always build in a native amd64 container (GitHub runners are x86_64) and
// cross-build the image for the requested architecture, so the heavy
// compilation runs at native speed instead of under QEMU emulation.
const buildPlatform = dagger.Platform("linux/amd64")
const tarball = "guix-binary-" + guixVersion + ".x86_64-linux.tar.xz"

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

func normalizeArch(arch string) string {
	if arch == "" {
		return "x86_64"
	}
	return arch
}

// setup builds an amd64 container with Guix installed (daemon not started).
func setup() *dagger.Container {
	return dag.Container(dagger.ContainerOpts{Platform: buildPlatform}).
		From("debian:stable-slim").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "--no-install-recommends",
			"curl", "ca-certificates", "xz-utils", "gnupg", "passwd", "netbase", "git", "python3"}).
		WithExec([]string{"curl", "-fsSL", "-o", "/tmp/" + tarball,
			"https://ftp.gnu.org/gnu/guix/" + tarball}).
		WithExec([]string{"tar", "-C", "/", "--warning=no-timestamp", "-xf", "/tmp/" + tarball}).
		WithExec([]string{"bash", "-c", setupScript})
}

// buildContainer runs the full pull + image build.
func buildContainer(arch string) *dagger.Container {
	src := dag.CurrentModule().Source()
	return setup().
		WithMountedDirectory("/workspace", src).
		WithExec([]string{"bash", "/workspace/pull.sh"},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		WithExec([]string{"bash", "/workspace/image.sh", arch},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true})
}

// Build assembles the Guix installation image and returns it as a directory
// containing guix-install-<arch>-linux.<ext>.
func (m *GuixIso) Build(
	ctx context.Context,
	// Architecture of the image: "x86_64" or "aarch64".
	// +optional
	arch string,
) *dagger.Directory {
	arch = normalizeArch(arch)
	return buildContainer(arch).Directory("/out")
}

// Debug returns the setup container for inspection without running the build.
func (m *GuixIso) Debug() *dagger.Container {
	return setup()
}
