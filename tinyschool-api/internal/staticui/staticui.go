package staticui

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var distEmbed embed.FS

// Handler serves the embedded Nuxt SPA. Existing files are returned as-is;
// unknown paths fall back to index.html for client-side routing.
func Handler() http.Handler {
	root, err := fs.Sub(distEmbed, "dist")
	if err != nil {
		panic("staticui: embed dist: " + err.Error())
	}
	fileServer := http.FileServer(http.FS(root))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		clean := path.Clean("/" + r.URL.Path)
		rel := strings.TrimPrefix(clean, "/")
		if rel == "" || rel == "." {
			http.ServeFileFS(w, r, root, "index.html")
			return
		}

		info, err := fs.Stat(root, rel)
		if err == nil && !info.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		}
		if err == nil && info.IsDir() {
			if _, indexErr := fs.Stat(root, path.Join(rel, "index.html")); indexErr == nil {
				fileServer.ServeHTTP(w, r)
				return
			}
		}

		http.ServeFileFS(w, r, root, "index.html")
	})
}
