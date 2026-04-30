EasyJSON
========

Server to convert Profiles RNS VIVO JSON-LD into a simplified JSON representation

In addition to being a lot easier for developers to work with, the
interface also features strong caching and failover support, in order
to maximize performance for end users.

Usage and API
-------------

Quick summary
- This service converts Profiles (VIVO/RNS/ORNG) JSON-LD into a simplified JSON representation for a single person/profile. It accepts multiple identifier types and returns a compact JSON object suitable for client consumption.

Endpoint
- The PSGI app is defined in app.psgi. It accepts GET requests with one identifier parameter (one of the keys listed below). Responses are JSON (application/json) and the app supports JSONP via the `callback` parameter.

Identifier query parameters (as accepted by app.psgi)
- `FNO`: FNO / FNO-like identifiers (example: `anirvan.chatterjee@ucsf.edu`)
- `Person`: Profiles internal Person ID (numeric)
- `EmployeeID`: Employee ID
- `EPPN`: eduPersonPrincipalName (will be mapped to UserName)
- `ProfilesURLName`: Pretty URL name (e.g. `anirvan.chatterjee`)
- `ProfilesNodeID`: Numeric Profiles node id; returns canonical profile URL directly
- `URL`: A full Profiles URL (canonical / pretty / historical `ProfileDetails.aspx`)

Examples
- PrettyURL (JSON):

  curl "http://localhost:5000/?ProfilesURLName=anirvan.chatterjee&source=myapp"

- FNO (JSON, force no cache):

  curl "http://localhost:5000/?FNO=anirvan.chatterjee@ucsf.edu&cache=never&source=myapp"

- ProfilesNodeID (JSONP):

  curl "http://localhost:5000/?ProfilesNodeID=370974&callback=mycb&source=myapp"

Parameters and behavior
- `source` (required): A free-text string identifying the caller (or send a Referer header). The app requires either a `source` parameter or a referer to help track usage and contact callers if needed.
- `cache`: `cache=fallback` (default) | `cache=always` | `cache=never`
  - `fallback` (default): try cache first; if not available, fetch from upstream and cache; in case of upstream failure it may return recently expired cache (subject to the cache policy).
  - `always`: always return cached data if available; do not fetch upstream (used to ensure fast, deterministic responses)
  - `never`: never use cache (forces a live fetch), and increases the HTTP timeout to allow longer fetch time
- `timeout`: number of seconds for the request to complete — this sets a soft `finish_by_time_in_epoch_seconds` that lowers UA timeouts dynamically
- `callback`: JSONP support; when provided the response Content-Type becomes `text/javascript` and the JSON is wrapped as `callback(JSON)`

Cache behavior and policy
-------------------------

- The module uses `ProfilesEasyJSON::CHI` for caching. There are several separate namespaces used by the code (identifier -> canonical URL mapping, canonical URL -> JSON, raw URL fetch cache for ORNG gadget fields, and some position/name caches).
- When upstream fetches fail, the code will attempt to fall back to expired cache entries if they exist and pass the cache policy check. The cache policy permits returning cached entries no older than 14 days (see `_verify_cache_object_policy`).
- `cache=always` will prevent upstream fetches and may return stale data; `cache=never` forces live fetch but adjusts timeouts to allow slower upstream responses.

Configuration
-------------

- `profilesdotjson.conf` (optional): used to store secrets/RC4 password for decrypting `emailEncrypted` fields in Profiles RDF. The code expects an RC4 password at key `RC4_PASSWORD` (first value used). Example format (simple key=value equal file):

  RC4_PASSWORD=supersecret

- The code will attempt to decrypt `emailEncrypted` fields using `Crypt::RC4` and Base64 decode if the config file contains the RC4 password. If not present, the code tries a vCard endpoint to retrieve the public email.

How data is fetched and processed
-------------------------------

- Two upstream endpoints are used:
  - `CustomAPI/v2/Default.aspx`: used to map identifiers (FNO, EmployeeID, Person, PrettyURL, etc.) to an internal `rdf:about` node URI for the person.
  - `/ORNG/JSONLD/Default.aspx`: used to fetch expanded JSON-LD for a given subject (node id) with `expand=true` and `showdetails=true`. This JSON-LD contains the `@graph` of items used to build the simplified JSON.
- The code parses the JSON-LD `@graph` into internal structures (`items_by_url_id`, `publications_by_author`, `research_activities_and_funding_by_role`, `orng_data`, etc.) and normalizes inconsistently shaped fields (singletons vs arrays, double-encoded JSON strings, chunked ORNG gadget data).
- A final hashref is composed (`Profiles => [ ... ]`) with normalized fields such as `Name`, `Email`, `ProfilesURL`, `Titles`, `Address`, `Publications`, `Education_Training`, `MediaLinks`, `GlobalHealth`, `ClinicalTrials`, `ResearchActivitiesAndFunding`, and more. The result is encoded to JSON and returned as the HTTP response body.

Testing
-------

- The repository includes tests that exercise many real Profiles records. Be aware these are integration-like tests and will call upstream Profiles servers; tests can be skipped when upstream data is missing.
- To run the tests locally:
  - Install dependencies (see `cpanfile`/`Cpanfile` or install required modules). Dependencies include `LWP::UserAgent`, `JSON`, `Data::Visitor::Callback`, `Crypt::RC4` (optional), `CHI`, `Test::More`, etc.
  - Run tests with: `prove -lv t/library-mega.t` or `perl -Ilib t/library-mega.t`
  - Individual tests may be skipped depending on upstream availability; the test suite expects many assertions but several are guarded with `SKIP` blocks when live data cannot be fetched.

Running locally
---------------

- Start the PSGI app with `plackup`:

  plackup -p 5000 app.psgi

  Then query: `curl "http://localhost:5000/?ProfilesURLName=anirvan.chatterjee&source=localtest"`

Troubleshooting
---------------

- If you see many upstream connection timeouts, consider increasing the `timeout` parameter in the client request or running with `cache=always` to avoid upstream fetches.
- If email fields are missing, verify `profilesdotjson.conf` contains the correct RC4 password if your Profiles instance uses encrypted publicly-visible emails. Otherwise, the module tries the vCard endpoint.
- Inconsistent or missing gadget data (ORNG) may be due to different ORNG gadget implementations; the code attempts to decode many shapes (string, array, chunked pieces) but if you see odd results, capture upstream JSON-LD and open an issue.
