# website/ — Ludo Royale pages for sungamestudio.com

Static pages for the studio site <https://sungamestudio.com> (Sun Game Studio),
deployed by hand. This folder is not part of the app, the backend or bot-play,
and nothing here is built or deployed automatically.

The studio site is a hand-built static site served by nginx behind Cloudflare,
from the web root `/var/www/gameplay/sungamestudio.com` with
`try_files $uri $uri.html $uri/ =404` (so `/brain-train` is `brain-train.html`).
The site's own files (`index.html`, `style.css`, `site.js`, the other game pages)
are **not** in this repository. The pages here reuse them by their root-relative
URLs, and the homepage changes are delivered as snippets plus a script that
inserts them.

## Files and where they go

| File in `website/` | Path in the web root | URL |
|---|---|---|
| `ludo-royale.html` | `ludo-royale.html` | `/ludo-royale` |
| `ludo-royale-logo.png` (app icon, 256 px) | `ludo-royale-logo.png` | `/ludo-royale-logo.png` |
| `ludo-royale-shots/` (screenshots, 1280×720 banner) | `ludo-royale-shots/` | `/ludo-royale-shots/…` |
| `ludo-royale/privacy/index.html` (**draft**) | `ludo-royale/privacy/index.html` | `/ludo-royale/privacy/` |
| `ludo-royale/legal/index.html` (generated) | `ludo-royale/legal/index.html` | `/ludo-royale/legal/` |
| `snippets/index-games-card.html` | inserted into `index.html` | homepage Games section |
| `snippets/footer-games-link.html` | inserted into every page footer | footer "Games" list |
| `snippets/footer-legal-link.html` | inserted into every page footer | footer "Legal" list |
| `snippets/sitemap-entries.xml` | inserted into `sitemap.xml` | |
| `apply_snippets.py` | not deployed | inserts the snippets into copies of the site's pages |
| `build_legal_page.py` | not deployed | builds `ludo-royale/legal/index.html` from the app's notices |

The app opens `https://sungamestudio.com/ludo-royale/legal/` for its open-source
notices when it is built with
`--dart-define=LEGAL_NOTICES_URL=https://sungamestudio.com/ludo-royale/legal/`
(default without it: the backend's `GET /legal/open-source`). Keep that path.

## Design

The pages use the site's own `/style.css` (night theme: navy ink and sun gold,
self-hosted Bricolage Grotesque and Inter), `/site.js` (phone menu and screenshot
viewer) and the same markup as `brain-train.html`:

- shell: `site-header` / `site-nav` / `menu-btn`, `site-footer` / `footer-grid` /
  `footer-col`, skip link;
- game page: `game-hero` + `game-hero-grid` + `title-row` + `game-icon` + `tags`,
  `phone-pair` / `phone-frame`, `section` + `section-head` + `eyebrow`, `steps`,
  `feature-grid three` with `ico`, `phones` / `phone` with `data-gallery`
  (lightbox), `notice`, `two-col` + `facts-table`, `cta-band`, `btn btn-soon`,
  `text-link`;
- privacy policy: `doc`, `doc-head`, `prose`, `card`, `table-wrap`, `doc-foot`
  (the structure of `/brain-train/privacy/`);
- open-source notices: `doc` / `doc-head` plus a small page-only `<style>` built
  from the site's CSS variables for the component index and the notice texts;
- homepage card: `game-card`, `game-media`, `status soon`, `game-body`,
  `game-head`, `tags`, `actions` (the Brain Train card pattern).

No new external dependencies, no trackers, no Cloudflare e-mail scripts: all
e-mail links are plain `mailto:`.

Images: screenshots are real iPhone-simulator captures of the app (status bar
cropped, friend codes blurred), cut to the site's 9:16 phone frame and saved as
WebP at 540×960 (thumbnails) and 720×1280 (lightbox), 20–70 KB each. The banner
(`ludo-royale-banner.jpg`, 1280×720, also the `og:image`) combines the crown logo
(`frontend/assets/branding/launch_logo_1024.png`) and the Ludo board. The logo is
`frontend/assets/branding/app_icon_1024.png` at 256×256 (44 KB).

## Preview locally

1. Make a scratch folder (outside the repo) and copy into it, from read-only
   copies of the live site: `index.html`, `sitemap.xml`, `style.css`, `site.js`,
   `fonts/`, `logo-mark.png`, `favicon.png`, the other game pages you want to
   check, and their images (or leave images out; only they will be missing).
2. Copy this folder's deployable files into it: `ludo-royale.html`,
   `ludo-royale-logo.png`, `ludo-royale-shots/`, `ludo-royale/`.
3. Insert the snippets into the copies:

   ```bash
   python3 website/apply_snippets.py /tmp/site/index.html /tmp/site/sitemap.xml \
     --footer-page /tmp/site/brain-train.html --footer-page /tmp/site/king-teen-patti.html
   ```

4. Serve it: `cd /tmp/site && python3 -m http.server 8099`, then open
   <http://localhost:8099/>, <http://localhost:8099/ludo-royale.html>,
   <http://localhost:8099/ludo-royale/privacy/> and
   <http://localhost:8099/ludo-royale/legal/>. `http.server` has no
   `try_files`, so extensionless links such as `/ludo-royale` only work on the
   real site; open the `.html` URL instead. The fonts must be in the same
   folder: the live site does not allow them to be loaded from another origin.

## Deploy (by hand)

Run these steps yourself; nothing here does them for you. `HOST` is the web
server, `ROOT=/var/www/gameplay/sungamestudio.com`.

1. **Review first.** The privacy policy is a draft: work through
   "Privacy policy: points to confirm" below, set its effective date, and remove
   the `<!-- DRAFT … -->` comments.
2. **Back up the web root.**

   ```bash
   ssh HOST 'tar czf ~/sungamestudio-$(date +%Y%m%d-%H%M).tgz -C /var/www/gameplay sungamestudio.com'
   ```

3. **Fetch copies of the pages that change** (homepage, sitemap and every page
   with the standard footer) into a local work folder:

   ```bash
   mkdir -p work/brain-train/privacy
   scp HOST:$ROOT/{index.html,sitemap.xml,brain-train.html,king-teen-patti.html,terms.html,404.html} work/
   scp HOST:$ROOT/brain-train/privacy/index.html work/brain-train/privacy/
   ```

4. **Insert the snippets** (dry run first; the script refuses, and writes
   nothing, if an anchor is missing or the page already has Ludo Royale):

   ```bash
   python3 website/apply_snippets.py work/index.html work/sitemap.xml \
     --footer-page work/brain-train.html --footer-page work/king-teen-patti.html \
     --footer-page work/terms.html --footer-page work/404.html \
     --footer-page work/brain-train/privacy/index.html --dry-run
   # then the same command without --dry-run; check: git diff --no-index <original> work/index.html
   ```

   What it does in `index.html`: inserts `snippets/index-games-card.html` after
   the Brain Train `<article class="game-card">` (and before
   `<div class="more-card">`); sets `style="grid-column: auto"` on
   `<div class="more-card">` so "More on the way" fills the free cell next to
   the third card (skip with `--keep-more-card-full-width`); inserts the footer
   links after `<li><a href="/brain-train">Brain Train</a></li>` and after
   `<li><a href="/brain-train/privacy/">Brain Train Privacy Policy</a></li>`.
   In `sitemap.xml`: the three URLs before `</urlset>`. A page whose footer
   lacks those anchors is refused (`privacy.html`, `refund.html` and
   `delete-account.html` were not available to check); add the footer `<li>`s
   there by hand if they have the same lists.

5. **Upload** the new files and the edited copies, keeping the owner and modes
   of the existing files (the web root's files belong to the `write` user):

   ```bash
   rsync -av website/ludo-royale.html website/ludo-royale-logo.png HOST:$ROOT/
   rsync -av website/ludo-royale-shots website/ludo-royale HOST:$ROOT/
   rsync -av work/ HOST:$ROOT/
   ```

6. **nginx needs no change**: `try_files $uri $uri.html $uri/ =404` serves
   `/ludo-royale` from `ludo-royale.html` and `/ludo-royale/privacy/` and
   `/ludo-royale/legal/` from their `index.html`, exactly like Brain Train.
7. **Purge Cloudflare's cache** for `/`, `/sitemap.xml` and the footer pages
   (or wait for their cache lifetime).
8. **Verify:**

   ```bash
   for u in /ludo-royale /ludo-royale/privacy/ /ludo-royale/legal/ /ludo-royale-logo.png \
            /ludo-royale-shots/ludo-royale-banner.jpg /ludo-royale-shots/01-classic-board-540.webp; do
     curl -s -o /dev/null -w "%{http_code} %{content_type} $u\n" "https://sungamestudio.com$u"
   done   # expect 200 and text/html, image/png, image/jpeg, image/webp
   curl -s https://sungamestudio.com/ | grep -c '/ludo-royale'      # > 0
   curl -s https://sungamestudio.com/sitemap.xml | grep ludo-royale
   ```

   Then open the homepage and `/ludo-royale` on a phone and a desktop browser.
9. **Roll back** if needed by restoring the tarball from step 2.

## Open-source notices: regenerate before each app release

The page must list the licences of exactly what ships in the app build.

```bash
cd frontend
flutter build bundle --release              # writes build/flutter_assets/NOTICES.Z
dart run tool/export_oss_notices.dart       # → backend/config/legal/open-source-notices.html
cd ..
python3 website/build_legal_page.py         # → website/ludo-royale/legal/index.html
python3 website/build_legal_page.py --check # exit 1 if the page is stale
```

`build_legal_page.py` copies the generated component index and every notice
byte for byte into the site's page shell, and refuses if any licence text in the
output differs from the source. Commit both generated files, then upload
`website/ludo-royale/legal/index.html` to `$ROOT/ludo-royale/legal/index.html`
(steps 2, 5, 7 and 8 above).

## Privacy policy: points to confirm

`ludo-royale/privacy/index.html` describes the app as the code and docs in this
repository show it (docs/authentication.md, docs/progression.md,
docs/rest-api.md, backend/migrations, frontend/lib/core/analytics,
frontend/lib/core/device). These statements could not be verified from the
repository and must be confirmed or changed before publishing:

- **Account deletion.** The app has no "Delete account" button and the backend
  has no deletion endpoint or tool. The page offers deletion by e-mail within 30
  days; someone must actually be able to do it. App Store and Google Play both
  require a deletion path for apps with accounts. `/delete-account` today covers
  King Teen Patti only, so the Ludo Royale pages link to the privacy policy's
  section 6 (`/ludo-royale/privacy/#delete`) instead.
- **Age 13+.** Nothing in the repository sets an age; the app has no age gate.
  The pages state 13+; the store age ratings must match.
- **Google Analytics retention** "at most 14 months" assumes a standard GA4
  property; set the property's retention to match.
- **Hosting.** The provider and the country of the servers are not documented;
  the page says only "servers operated by Sun Game Studio". Name the hosting
  provider (a processor) and the location if required.
- **Logs and backups.** No retention period is documented for server logs,
  load-balancer/proxy logs or database backups (PITR). The page says the game
  server does not write IP addresses to its logs, which is true of the Go code;
  any proxy or load balancer in front of it is not covered.
- **Sign-in providers.** Only Google sign-in is configured today; Facebook and
  Apple are implemented but pending configuration (README "Status").
- **Responses within 30 days** to privacy requests mirrors the Brain Train
  policy; confirm the studio can meet it.
- The provider's first name becomes a player's public display name by default
  (it is not checked against the offensive-words list); this is disclosed.
