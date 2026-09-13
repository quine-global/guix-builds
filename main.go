// A Dagger module that builds a reproducible Guix installation image
// inside a container (x86_64 ISO by default; pass --arch for arm64).
//
// Edit channels.scm to change which Guix commit is used, then run:
//
//	dagger call build export --path=./out
//	dagger call build --arch=aarch64 export --path=./out
//
// The exported directory contains the installation image plus a
// guix-cache.tar.gz store snapshot. Feed that snapshot back via --cache on
// the next run to skip recompiling derivations:
//
//	dagger call build --arch=aarch64 --cache=./cache/guix-cache.tar.gz \
//	    export --path=./out

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

func normalizeArch(arch string) string {
	if arch == "" {
		return "x86_64"
	}
	return arch
}

// setup builds a container with Guix installed for the given architecture,
// restoring a previous store cache on top if provided (daemon not started).
func setup(arch string, cache *dagger.File) *dagger.Container {
	tarball := "guix-binary-" + guixVersion + "." + arch + "-linux.tar.xz"
	c := dag.Container(dagger.ContainerOpts{Platform: platformFor[arch]}).
		From("debian:stable-slim").
		WithEnvVariable("DEBIAN_FRONTEND", "noninteractive").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "--no-install-recommends",
			"curl", "ca-certificates", "xz-utils", "gnupg", "passwd", "netbase"}).
		WithExec([]string{"curl", "-fsSL", "-o", "/tmp/" + tarball,
			"https://ftp.gnu.org/gnu/guix/" + tarball}).
		WithExec([]string{"tar", "-C", "/", "--warning=no-timestamp", "-xf", "/tmp/" + tarball}).
		WithExec([]string{"bash", "-c", setupScript})
	if cache != nil {
		c = c.WithMountedFile("/tmp/guix-cache.tar.gz", cache).
			WithExec([]string{"bash", "-c",
				"[ -s /tmp/guix-cache.tar.gz ] && tar -xzf /tmp/guix-cache.tar.gz -C / || true"})
	}
	return c
}

// buildContainer runs the full pull + image build, then snapshots the Guix
// store (plus daemon database) into /out/guix-cache.tar.gz so it can be
// reused on the next run. It returns the container with both artifacts in /out.
func buildContainer(arch string, cache *dagger.File) *dagger.Container {
	src := dag.CurrentModule().Source()
	return setup(arch, cache).
		WithMountedDirectory("/workspace", src).
		WithExec([]string{"bash", "/workspace/pull.sh"},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		WithExec([]string{"bash", "/workspace/image.sh", arch},
			dagger.ContainerWithExecOpts{InsecureRootCapabilities: true}).
		WithExec([]string{"bash", "-c",
			"tar -czf /out/guix-cache.tar.gz -C / gnu/store var/guix/db var/guix/profiles root/.config/guix"})
}

// Build assembles the Guix installation image and a snapshot of the Guix
// store cache, and returns them as a directory containing:
//
//	guix-install-<arch>-linux.<ext>  the installation image
//	guix-cache.tar.gz                store snapshot for reuse via --cache
func (m *GuixIso) Build(
	ctx context.Context,
	// Architecture of the image: "x86_64" or "aarch64".
	// +optional
	arch string,
	// Optional store cache from a previous build to reuse derivations.
	// +optional
	cache *dagger.File,
) *dagger.Directory {
	arch = normalizeArch(arch)
	return buildContainer(arch, cache).Directory("/out")
}

// Debug returns the setup container for inspection without running the build.
func (m *GuixIso) Debug(
	// +optional
	arch string,
) *dagger.Container {
	return setup(normalizeArch(arch), nil)
}
