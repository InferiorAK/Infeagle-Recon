#!/usr/bin/python3

import asyncio, aiohttp, argparse, sys, os
from urllib.parse import urlparse
from colorama import Fore, Style, init
from tqdm import tqdm as _tqdm

init(autoreset=True)

CONCURRENCY = 10
TIMEOUT     = 10
INPUT_FILE  = "urls.txt"
OUTPUT_FILE = "live.txt"
FOLLOW_REDIRECTS = False

CO = "\033[38;5;208m"
CG = Fore.GREEN
CR = Fore.RED
CC = Fore.CYAN
CY = Fore.YELLOW
R  = Style.RESET_ALL

BANNER = f"""\
{CO}
  ██╗     ██╗██╗   ██╗███████╗       ██╗   ██╗██████╗ ██╗
  ██║     ██║██║   ██║██╔════╝       ██║   ██║██╔══██╗██║
  ██║     ██║██║   ██║█████╗  ██████╗██║   ██║██████╔╝██║
  ██║     ██║╚██╗ ██╔╝██╔══╝  ╚═════╝██║   ██║██╔══██╗██║
  ███████╗██║ ╚████╔╝ ███████╗        ╚██████╔╝██║  ██║███████╗
  ╚══════╝╚═╝  ╚═══╝  ╚══════╝         ╚═════╝ ╚═╝  ╚═╝╚══════╝

   ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗███████╗██████╗
  ██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝██╔════╝██╔══██╗
  ██║     ███████║█████╗  ██║     █████╔╝ █████╗  ██████╔╝
  ██║     ██╔══██║██╔══╝  ██║     ██╔═██╗ ██╔══╝  ██╔══██╗
  ╚██████╗██║  ██║███████╗╚██████╗██║  ██╗███████╗██║  ██║
   ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
{R}
  {CO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{R}
  {CC}Tool{R}    Async HTTP Reachability Probe & Live URL Filter
  {CC}Author{R}  InferiorAK · github.com/InferiorAK
  {CC}Method{R}  aiohttp async · HTTPS→HTTP fallback
  {CC}Output{R}  Status-matched base URLs (default: 200,302)
  {CO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{R}"""

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
}

def normalize(url: str) -> str:
    url = url.strip().rstrip("/")
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    return url

async def check_live(session, url, timeout, sem, follow_redirects):
    async with sem:
        to = aiohttp.ClientTimeout(total=timeout)
        try:
            async with session.get(url, timeout=to, ssl=False, allow_redirects=follow_redirects) as r:
                return url, True, r.status
        except Exception:
            if url.startswith("https://"):
                try:
                    async with session.get("http://" + url[8:], timeout=to, ssl=False, allow_redirects=follow_redirects) as r:
                        return url, True, r.status
                except Exception:
                    pass
            return url, False, 0

async def run(targets, timeout, concurrency, output, allowed, silent, follow_redirects=False):
    sem = asyncio.Semaphore(concurrency)
    conn = aiohttp.TCPConnector(limit=concurrency, ssl=False)
    live, seen_bases = [], set()

    async with aiohttp.ClientSession(connector=conn, headers=HEADERS) as session:
        tasks = [check_live(session, t, timeout, sem, follow_redirects) for t in targets]

        with open(output, "w") as out_f, _tqdm(
            total=len(tasks), unit=" hosts", colour="cyan",
            desc="  Checking",
            bar_format="  {l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}, {rate_fmt}]",
            dynamic_ncols=True, leave=True, disable=False,
        ) as pbar:
            for coro in asyncio.as_completed(tasks):
                url, is_live, status = await coro

                if is_live:
                    if status in allowed:
                        live.append(url)
                        if url not in seen_bases:
                            seen_bases.add(url)
                            out_f.write(url + "\n")
                            out_f.flush()
                        if not silent:
                            c = CG if status == 200 else CO
                            pbar.write(f"  {c}[LIVE]  {status}{R}  {url}")
                    elif not silent:
                        pbar.write(f"  {CR}[SKIP]  {status}{R}  {url}")
                elif not silent:
                    pbar.write(f"  {CR}[DEAD]   ---{R}  {url}")

                pbar.update(1)

    return live

def main():
    for i, a in enumerate(sys.argv):
        if a == "-silent":
            sys.argv[i] = "--silent"
        elif a == "-mc" and i + 1 < len(sys.argv):
            sys.argv[i] = "--mc"

    parser = argparse.ArgumentParser(description="Live URL Checker")
    parser.add_argument("-u", "--url", help="Single URL to check")
    parser.add_argument("-f", "--file", default=INPUT_FILE,  help=f"Input file  (default: {INPUT_FILE})")
    parser.add_argument("-o", "--output", default=OUTPUT_FILE, help=f"Output file (default: {OUTPUT_FILE})")
    parser.add_argument("-s", "--silent", action="store_true", help="Suppress banner & terminal output")
    parser.add_argument("--no-banner", action="store_true", default=False, help="Suppress only the banner")
    parser.add_argument("-c", "--concurrency", type=int, default=CONCURRENCY, help=f"Concurrency (default: {CONCURRENCY})")
    parser.add_argument("-t", "--timeout", type=int, default=TIMEOUT,     help=f"Timeout sec  (default: {TIMEOUT})")
    parser.add_argument("--mc",  default="200,302", help="Allowed status codes (comma-sep, default: 200,302)")
    parser.add_argument("--fr", "--follow-redirects", action="store_true", default=FOLLOW_REDIRECTS, help="Follow redirects (default: off)")
    args = parser.parse_args()

    allowed = {int(c.strip()) for c in args.mc.split(",") if c.strip().isdigit()}

    if not args.silent and not args.no_banner:
        print(BANNER)

    targets = []
    if args.url:
        targets = [normalize(args.url)]
    elif args.file and os.path.isfile(args.file):
        try:
            with open(args.file) as f:
                targets = [normalize(l) for l in f if l.strip() and not l.strip().startswith("#")]
        except FileNotFoundError:
            msg = f"[!] File not found: {args.file}"
            if args.silent:
                print(msg, file=sys.stderr)
            else:
                print(f"  {CR}{msg}{R}")
            sys.exit(1)
    elif not sys.stdin.isatty():
        targets = [normalize(l) for l in sys.stdin if l.strip()]

    if not targets:
        if not args.silent:
            print(f"  {CR}[!] No targets to check.{R}")
        sys.exit(0)

    if not args.silent:
        src = args.url or ("stdin" if not sys.stdin.isatty() else args.file)
        W = 56
        print(f"  {CC}{'─' * W}{R}")
        print(f"  {'Input':<18} {src}")
        print(f"  {'Output':<18} {args.output}")
        print(f"  {'Targets':<18} {len(targets):,} URLs")
        print(f"  {'Concurrency':<18} {args.concurrency}")
        print(f"  {'Timeout':<18} {args.timeout}s")
        print(f"  {'Match codes':<18} {', '.join(map(str, sorted(allowed)))}")
        print(f"  {'Follow redirects':<18} {args.fr}")
        print(f"  {CC}{'─' * W}{R}\n")

    live = asyncio.run(run(targets, args.timeout, args.concurrency, args.output, allowed, args.silent, args.fr))

    if not args.silent:
        saved = len(set(f"{urlparse(u).scheme}://{urlparse(u).netloc}" for u in live))
        total = len(targets)
        print(f"\n  {CC}{'─' * W}{R}")
        print(f"  {'Live (saved)':<18} {CG}{len(live):>6,}{R}")
        print(f"  {'Dead / Skip':<18} {CR}{total - len(live):>6,}{R}")
        print(f"  {'Saved (unique)':<18} {CY}{saved:>6,}{R}  →  {args.output}")
        print(f"  {CC}{'─' * W}{R}\n")

if __name__ == "__main__":
    main()
