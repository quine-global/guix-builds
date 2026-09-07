// A Dagger module that builds a reproducible Guix installation ISO
// inside a container (cross-built for x86_64).
//
// Edit channels.scm to change which Guix commit is used, then run:
//
//	dagger call build export --path=./guix-install-x86_64-linux.iso

package main

import (
	"context"

	"dagger/guix-iso/internal/dagger"
)

const (
	guixVersion = "1.5.0"
	arch        = "x86_64"
	platform    = "linux/amd64"
	tarball     = "guix-binary-" + guixVersion + "." + arch + "-linux.tar.xz"
)

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

// setup builds the x86_64 container with Guix installed (daemon not started).
func setup() *dagger.Container {
	return dag.Container(dagger.ContainerOpts{Platform: platform}).
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
func (m *GuixIso) Build(ctx context.Context) *dagger.File {
	src := dag.CurrentModule().Source()

	return setup().
		WithMountedDirectory("/workspace", src).
		WithExec([]string{"bash", "/workspace/pull.sh"},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		WithExec([]string{"bash", "/workspace/image.sh"},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		File("/out/guix-install-" + arch + "-linux.iso")
}

// Debug returns the setup container for inspection without running the build.
func (m *GuixIso) Debug() *dagger.Container {
	return setup()
}
