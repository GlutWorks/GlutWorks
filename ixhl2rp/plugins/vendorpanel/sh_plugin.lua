local PLUGIN = PLUGIN

PLUGIN.name = "Vendor Panel"
PLUGIN.author = "GlutWorks"
PLUGIN.description = "Trading with a Helix vendor happens on a world panel beside them instead of a window."
PLUGIN.readme = [[
Tapping Use on a vendor (Helix's `vendor` plugin) opens a world panel (ix.worldui) beside them instead of the
centred trade window: what they sell (name, price, stock where the vendor tracks it) and what they buy of yours,
under two headings, with how much money you and they have at the top. Choosing a row buys or sells one trade unit
through Helix's own `ixVendorTrade`, so every server rule still applies, the stacking plugin's `tradeAmount`
included. Rows you cannot afford, or that are sold out, are greyed but can still be chosen, so the refusal is felt.

What the server says about a trade (bought, sold, refused) is a private chat line with a sound instead of a
notice; a trade the server refuses without a word gets the refusal sound. The panel follows `ixVendorStock`,
`ixVendorMoney` and the inventory, and when it closes for any reason the server is told (`ixVendorClose`), as
the window did. The vendor editor (staff) is still Helix's window.
]]

ix.util.Include("sv_plugin.lua")
ix.util.Include("cl_plugin.lua")
