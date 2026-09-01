# 06-cts-tracker

Turns on the CTS audit tracker in one account, with no OBS bucket and no LTS
transfer. Events are still recorded and visible in the CTS console for about
7 days, but the account pays nothing for log storage.

Use it for accounts that only need the central organization tracker (from
06-compliance-audit) to capture their history. The observability environment
applies it to every account listed in cts_no_transfer_accounts.
