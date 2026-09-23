> Economy integration is preparation only: current permissions block checkout; sales and player-shop funds are unavailable. See [FEATHER_PORT.md](FEATHER_PORT.md) before starting this version.

# 🛒 BCC Shops – Advanced Shop System for RedM

**BCC Shops** is a powerful and dynamic shop management system for RedM. It allows servers to create immersive NPC-run stores and fully functional player-owned shops, all configurable via an in-game menu. No need to touch config files!

---



## 🚀 Features

- 🧍 **NPC Shops**  
  Create NPC-operated shops with customizable blips, coordinates, and ped models.

- 🧑‍🌾 **Player-Owned Shops**  
  Players can own and manage their own shops, complete with inventory caps, ledgers, and sale tracking.



- 🔧 **Everything Configurable In-Game**  
  No complex config files — all shop settings can be created and edited directly through the management UI.



- 🧾 **Item & Weapon Categories**  
  Manage shop inventory with category support, separate stock for buy/sell quantities, and level restrictions.

- 💰 **Ledger System**  
  Track shop funds with deposit and withdrawal options, including automated transaction logging.

- 🤖 **NPC Customer Simulation**  
  NPCs dynamically spawn, walk to your shop, simulate purchases, and buy random items or weapons.

- 📢 **Discord Webhook Logging**  
  Important events like purchases, deposits, and edits are sent to a designated Discord channel for transparency.

- 🧭 **Custom Blip System**  
  Assign map markers to shops with visual identifiers (supports image and hash-based blips).

- 🧠 **Feather Menu Interface**  
  All menus are powered by `feather-menu`, offering a clean, responsive experience.
  Notifications are delivered through Feather.

- 🌍 **Multilingual Support**  
  Localized in English, Romanian, and Polish through `Feather.Locale.register`, with `_U("key")` for translation calls.

---

## 📦 Dependencies

This system depends on the following RedM/FXServer resources:

- `oxmysql`
- `feather-core`
- `feather-character`
- `feather-roles`
- `feather-inventory`
- `feather-weapons`
- `feather-toolkit`
- `feather-notify`
- `feather-menu-v2`
- `bcc-banks`

---

## ⚙️ Installation

1. **Download the latest version of bcc-shops** into your server’s `resources/` folder.

2. **Add `bcc-shops` to your `server.cfg`** after all dependencies:
   ```txt
   ensure oxmysql
   ensure feather-core
   ensure feather-character
   ensure feather-roles
   ensure feather-inventory
   ensure feather-weapons
   ensure feather-toolkit
   ensure feather-notify
   ensure feather-menu-v2
   ensure bcc-banks
   ensure bcc-shops
   ```

3. **Start the server once** to auto-generate the required database tables.

---

## 🔧 Configuration

Basic settings are available in `config.lua`:

- `defaultlang` – Fallback locale (`en_us`, `ro`, or `pl`); Feather account preferences select the player locale
- `keys.access` – Interaction key for shop prompt (default: **G**)
- `ManageShopsCommand` – Command that opens the admin management menu
- `Webhook` – Global Discord webhook URL
- `ManagementRoles` – Controls admin access to management UI
- `BlipStyles` – Configure available blip icons
- `NPC` – Control NPC buyer behavior and spawn points

> 📝 All critical shop settings like positions, peds, inventory, and labels are handled directly through the in-game UI — no need to edit config files.

---

## 🧑‍💼 Usage

- **Players** press the configured key to access nearby shops.
- **Shop owners** can manage inventory, prices, and funds via the in-game interface.
- **Admins** use the configured command to create, edit, or delete shops.
- **NPCs** will dynamically simulate buyers and engage in item or weapon purchases.


### ♻️ Selling Items to Shops

- When **players sell** an item to a shop, that shop’s **`buy_quantity`** for the item **increases**.  
  *If you enforce an intake cap, the shop’s **`sell_quantity`** is reduced accordingly.*

- If the shop **didn’t have that item listed yet**, it’s added to the shop with **`buy_price = 0`**.  
  This lets shops **collect** items from players without instantly listing them for sale.

- An item becomes **buyable by customers** only when **both** are true:
  - `buy_quantity > 0`
  - `buy_price > 0`  
  If `buy_price` remains **0**, the item stays **hidden/unavailable** in the Buy menu even if the shop has stock.

- **Player-owned shops:** the amount paid to the seller is taken from the shop **ledger** — ensure sufficient funds to accept sales.  
  **NPC shops:** sellers are paid by the system; **no ledger required**.

- **Withdraw collected stock:** shop owners can open **Manage Items → Remove Items** and take any amount from the shop’s stock back into their inventory.
