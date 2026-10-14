# 🧩 Artifacts Manager

This folder of the EmBi platform (`CMake/ArtifactsHandler`) provides a **CMake-based automation tool** for managing build artifacts and their versions across multiple repositories.
The system allows user to define which artifacts and versions are required, then automatically downloads the necessary components.
The only software user needs available in system is GIT and CMake. Every other component necessary for project build shall be available through this module.

---

## ⚙️ Overview

The **Artifacts Manager** use a configuration file (`ArtifactsConfig.txt`) that lists the required artifacts and their versions.
When **Artifacts Manager** is executed, it performs the following steps:

1. **Clones** the artifacts root repository.
2. **Locates** the corresponding artifact submodule.
3. **Checks out** the repository at that exact commit.
4. **Install** the cloned artifact.
5: **Initialize** the installed artifact.

This approach ensures **minimal network usage** and **fast synchronization** between the build environment and artifact repositories.

### 1: Cloning
The root artifactory repository is cloned (if not exist) without initialization of submodules. This achieve minimal network usage and speed up whole process.

### 2: Location
The system iterates through all artifacts configured in `ArtifactsConfig.txt` and finds correct artifact through searching folders in artifacts root repository. 
The search is done as case-insesitive to reduce possible problems with configuration.

### 3: Checkout
After localization of artifact submodule, the required artifact version is checked-out. Every release for artifact is located in separate branch. 
If user selects `latest` instead of numerical version, the list of branches is downloaded once a day and latest version is checked. If newer version has been found, the system will use it.
The date of the last check is stored separately for Bin and Core part of every artifact in file `.LatestCheck` in the artifacts cache folder (e.g. `ArtifactsCache/doxygen/Core/.LatestCheck`), so the check is shared by all projects using the same cache. If the remote is not reachable (or OFFLINE mode is active), the newest cached version is used. A cached version newer than the latest remote one is not replaced.
User can select sub-version of artifact. This represents version of artifact miscelaneous functionality (artifact itself handler). This functionality contain necessary functionality for artifact initialization and usage.
The release branch name consist:
- the release version (e.g. `15.2.0`)
- the target operating system (e.g. `Win`, `Unix`, `DarwinARM`)
The checkout is done as a shallow clone (`--depth=1`) to minimize network traffic and memory space and speed up process.

### 4: Installation
The artifact shall be installed after check-out. The installation process consist of artifact archive extraction into local installation folder and copy of necessary files providing artifact handler from artifact repository.

### 5: Initialization
When the artifact is installed it shall be initialized before build to provide necessary informations for build itself. 
In most cases initialization updates the system PATH variable with path to current artifact. This path is assigned to the begin of system PATH to provide artifact functionality before installed ones.

---

## 📄 Artifacts configuration

Artifacts can be configured by multiple options:
- Using `ArtifactsConfig.txt` file located in `${CMAKE_SOURCE_DIR}`
- Specified location of `ArtifactsConfig.txt` through parameter `CONFIG_FILE_PATH`
- Specified list of artifacts through parameter or environment variable `ARTIFACTS_HANDLER_REQ_LIST`

### Using `ArtifactsConfig.txt` file located in `${CMAKE_SOURCE_DIR}`
The location of this configuration file shall be in cmake root directory (`${CMAKE_SOURCE_DIR}`).
The configuration file shall use syntax `ArtifactName;Version;Subversion` where:
- **ArtifactName** – the name of the artifact module (case-insensitive)  
- **Version** – corresponds to a artifact release (or `latest` for the newest version)  
- **Subversion** – corresponds to a artifact handler version (or `latest` for the newest commit)
```
gcc-arm-none-eabi;14.3.1;latest
ninja;latest;latest
doxygen;latest;latest
```

The path to the artifacts location can be configured through first line in ArtifactsConfig.txt. If the line begins with "ROOT_REPO_PATH=" the system will use this path for the artifacts location. 
```
ROOT_REPO_PATH=D:/Artifacts
gcc-arm-none-eabi;14.3.1;latest
ninja;latest;latest
doxygen;latest;latest
```

### Specified location of `ArtifactsConfig.txt` through parameter `CONFIG_FILE_PATH`
If configuration file is located in different location than `${CMAKE_SOURCE_DIR}`, user can specify path to this file through parameter `CONFIG_FILE_PATH`.
```bash
cmake -DCONFIG_FILE_PATH=/path/to/config/ -B ...
```

### Specified list of artifacts through parameter or environment variable `ARTIFACTS_HANDLER_REQ_LIST`
The list of artifacts of the configuration file can be replaced by parameter (or environment
variable) `ARTIFACTS_HANDLER_REQ_LIST`. Artifacts are separated by `,`, every artifact has the
same format as a line of `ArtifactsConfig.txt`. Other values (cache path, root repository URL)
are still read from the configuration file.
```bash
cmake -DARTIFACTS_HANDLER_REQ_LIST="gcc-arm-none-eabi;14.3.1;latest,ninja;latest;latest,doxygen;latest;latest" -B ...
```

### Cache folder of the artifacts
The cache folder (permanent storage of the downloaded artifacts, shared by all projects) is taken from the first source that is set:
1. parameter `-DARTIFACTS_HANDLER_CACHE_PATH=D:/Artifacts`
2. environment variable `ARTIFACTS_HANDLER_CACHE_PATH`
3. `ArtifactsConfig.txt`
4. default folder `Temp/Cache` of the handler

A path of one operating system is not valid on another one, so `ArtifactsConfig.txt` holds the path per operating system of the host (the file can be shared by Windows, Linux and macOS):
```
ARTIFACTS_HANDLER_CACHE_PATH_WIN=C:\ArtifactsCache
ARTIFACTS_HANDLER_CACHE_PATH_UNIX=/opt/ArtifactsCache
ARTIFACTS_HANDLER_CACHE_PATH_MAC=/Users/me/ArtifactsCache
```
Only the line of the host is used, the line of another system is skipped. When there is no line for the host, the default folder is used. The generic line `ARTIFACTS_HANDLER_CACHE_PATH=<path>` still works as a fallback, but it is ignored if it is a path of another system than the host (`C:\...` or `\\server\share` on Linux / macOS, `/opt/...` on Windows). The existence of the folder is not checked, it is created when the first artifact is installed.

Tools that read the cache outside of the handler (VSCode setup, integration testing) use `ArtifactsHandler_Get_ArtifactsCachePath` (it reads the configuration through `ConfigFileHandler_Get_CachePath`), they do not parse `ArtifactsConfig.txt` themselves.

### Use of the functions without starting the handler
`ArtifactsHandler.cmake` starts the handler when it is included (the `CMakeLists.txt` of the projects do that) and in script mode (`cmake -P`). A script that needs only its functions sets `ARTIFACTS_HANDLER_NO_RUN` before the include, nothing is installed or downloaded then:
```cmake
set(ARTIFACTS_HANDLER_NO_RUN TRUE)
include("${EMBI_PLATFORM_DIR}/CMake/ArtifactsHandler/ArtifactsHandler.cmake")
unset(ARTIFACTS_HANDLER_NO_RUN)

ArtifactsHandler_Get_ArtifactsCachePath("${PROJECT_DIR}/ArtifactsConfig.txt" CACHE_PATH)
```
Include the file in the scope of the script, not inside of a function - the functions use the variables set by the include.

---

## OS support
- On **Windows**, the manager automatically selects branches ending with `-Win`.
- On **Linux**, it selects branches ending with `-Unix`.
- On **MacOS **, it selects branches ending with `-DarwinARM`
- If a branch or commit cannot be found, the script skips that artifact with a warning. 

> Please contact admin with request for another OS support.

---

## 🧠 Implementation Notes

- The system uses **CMake’s `execute_process()`** to invoke Git commands.
- Repositories are handled with **shallow fetches** (`--depth=1`) to minimize size.
- Artifact names are compared **case-insensitively**, allowing flexible configuration formatting.
- The script supports incremental operation — already cloned repositories are reused.

---

## 📁 Directory Layout

```
ArtifactsManager/
├── README.md              # Readme file.
├── ArtifactsHandler.cmake # The main management script
└── Cache/
    ├── RootRepo/          # Root repository with submodules
    └── Artifacts/         # Artifacts installation folder
```

---

## 🚀 Usage

Run the CMake script directly:

```bash
cmake -P ArtifactsHandler.cmake
```

Optionally, you can integrate it into your existing CMake build or CI pipeline to automatically fetch the correct artifact versions before building.

User can configure path to the desired location for the artifacts by setting argument "ROOT_REPO_PATH".

```bash
cmake -P -DROOT_REPO_PATH="D:/Artifacts" ArtifactsHandler.cmake
```

---

## 🧩 Example Workflow

1. Update `ArtifactsConfig.txt` with desired versions  
2. Run:
   ```bash
   cmake -P ArtifactsHandler.cmake
   ```
3. The script:
   - Clones the root artifacts repository (if not already cloned)
   - Finds and fetches the correct branch and commit for each artifact
4. Your environment is now ready with all required artifact versions.

---

## 🛠️ Requirements

- **CMake ≥ 3.21**
- **Git ≥ 2.20**
- Network access to your artifact repositories (e.g. Azure DevOps)

---

## License

This repository consolidates components from STMicroelectronics packages.
Individual components retain their respective licenses. Refer to each folder for details.

---

## Update of a clone made before the handler became a folder of the platform

The handler used to be the Git submodule `CMake/ArtifactsHandler`. In a clone where this submodule is
initialized, checkout of a newer platform commit (`git checkout`, `git pull`, `git submodule update --remote
EmBi_Platform` of the project) stops with *"The following untracked working tree files would be overwritten
by checkout"* - nothing is changed. One-time fix in the folder of the platform (it keeps the `Temp` folder
with the downloaded artifacts and the clone of the root repository):

```bash
mv CMake/ArtifactsHandler/Temp <folder outside of the repository>/ArtifactsHandler_Temp
git submodule deinit -f -- CMake/ArtifactsHandler
git checkout <commit or branch of the platform>
mv <folder outside of the repository>/ArtifactsHandler_Temp CMake/ArtifactsHandler/Temp
```

`Temp` and `Cache` of the handler are ignored by the `.gitignore` of this folder. The leftover of the
submodule in the git directory (`modules/CMake/ArtifactsHandler`) is harmless and can be deleted.

---

## Authors

- **Mr.Nobody** — [embedbits.com](https://embedbits.com)

Contributions are welcome! Please open a pull request.

---

## 🌐 Useful Links

- [STM32CubeIDE](https://www.st.com/en/development-tools/stm32cubeide.html)
- [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/)
- [Embedbits Github](https://github.com/Embedbits)
- [CC BY-NC 4.0 License](https://creativecommons.org/licenses/by-nc/4.0/)