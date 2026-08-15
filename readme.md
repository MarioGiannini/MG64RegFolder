# MG64RegFolder

**MG64RegFolder** is a lightweight, high-performance Windows Registry utility written in **Free Pascal** and built using the **Lazarus IDE**. It allows users to search, analyze, and replace registry keys, value names, and value data across system hives with optional multi-level undo capabilities and robust logging.

---

## 🌟 Key Features

- 🔍 **Advanced Registry Search & Replace**: Search and replace across Registry Key names, Value names, and String/Binary/DWORD/QWORD data types.
- ↩️ **Optional Undo / Rollback Engine**: Automatically generates backup restore points (`.reg` files or internal change logs) prior to applying any modification, allowing one-click reversals.
- 📁 **Targeted Folder / Key Scope**: Scope operations to specific root keys (`HKEY_CURRENT_USER`, `HKEY_LOCAL_MACHINE`, etc.) or custom sub-key paths (folders).
- ⚡ **Native Performance**: Built entirely in Free Pascal for maximum speed, minimal memory usage, and zero external dependencies (no .NET Framework or Java required).
- 🛡️ **Safe Mode & Preview**: Dry-run mode to inspect and review potential replacement operations before writing changes to the Windows Registry.
- 📝 **Detailed Logging**: Export structured execution logs in plain text or CSV format for auditing and administrative records.

---

## 💻 Tech Stack & Requirements

- **Language**: Free Pascal (FPC 3.2.0+)
- **IDE**: Lazarus IDE (v2.0+)
- **Operating System**: Windows 7 / 8 / 10 / 11 / Server 2012+ (32-bit & 64-bit)
- **Privileges**: Administrator privileges required for modifications under `HKEY_LOCAL_MACHINE` and system-protected keys.

---

## 🏗️ Building from Source

### Prerequisites

1. Download and install **Lazarus IDE** from [lazarus-ide.org](https://www.lazarus-ide.org/).
2. Clone this repository:
   ```bash
   git clone https://github.com/your-username/MG64RegFolder.git
   cd MG64RegFolder
   ```

### Compilation via Lazarus GUI

1. Launch **Lazarus IDE**.
2. Open project: `File` ➔ `Open...` ➔ Select `MG64RegFolder.lpi`.
3. Select build mode (e.g., `Release` or `Debug`) from `Run` ➔ `Compile Many Modes...` or project options.
4. Press `Shift + F9` (or `Run` ➔ `Build`) to compile.
5. The output binary will be generated in the `bin/` or project folder.

### Compilation via Command Line (`lazbuild`)

```bash
lazbuild --build-mode=Release MG64RegFolder.lpi
```

---

## 🚀 Usage

1. **Run as Administrator**: Right-click `MG64RegFolder.exe` and select **Run as Administrator** to ensure full permissions to registry hives.
2. **Select Target Scope**:
   - Choose the Root Hive (`HKCU`, `HKLM` ).
   - Specify the target SubKey path (e.g., `SOFTWARE\MyCompany\Application`).
3. **Configure Search & Replace**:
   - Enter **Search Pattern** and **Replace Pattern**.
   - Select found items, and click **Search** or **Replace**
   - Save changes to a LOG file.
4. **Rolling Back Changes**:
   - Click the **Undo** button, and select the LOG file you want undone.

---

## 📁 Repository Structure

```
MG64RegFolder/
├── MG64RegFolders.ico          # program icon
├── MG64RegFolder.lpi           # Lazarus Project Information file
├── MG64RegFolder.lpr           # Lazarus Project Source file
├── umainform.pas               # Main application GUI logic
├── umainform.lfm               # Form layout specification
├── uregistrysearchthread.pas   # A class to support threaded registry searching
├── uregistrytreeview.pas       # A TreeView-based class that supports navigating registry keys
├── LICENSE                     # License agreement
└── README.md                   # Project README
```

---

## ⚠️ Safety Disclaimer

> **Caution**: Modifying the Windows Registry can cause system instability or prevent Windows from booting if critical system keys are improperly edited or deleted. Always backup your registry or enable the **Undo / Backup Point** feature in MG64RegFolder before executing replacements.

---

## 📜 License

This project is open-source and released under the **MIT License**. See the [LICENSE](LICENSE) file for more details.