# Z_ABAPGIT_ADT_EXPORT

Export ABAP packages as abapGit-compatible ZIP files via a custom ADT REST endpoint.

## What it does

Registers a custom ADT resource handler at `/sap/bc/adt/abapgit/export/packages` that wraps abapGit's built-in serialization (`ZCL_ABAPGIT_ZIP=>EXPORT`).
This allows any HTTP client to export an ABAP package as a ZIP file — no SAP GUI needed.

```
GET /sap/bc/adt/abapgit/export/packages?package=Z_MY_PKG
Accept: application/zip

-> 200 OK (ZIP binary, full abapGit format)
```

## Why

- Extract custom ABAP code from SAP for migration, analysis, or version control
- Automate bulk export of Z-packages (the test system has 2,548 Z-objects in 187 packages)
- No basis involvement needed — piggybacks on the existing `/sap/bc/adt/` SICF node via BAdI registration

## Prerequisites

- SAP_BASIS >= 740 SP05
- [abapGit](https://abapgit.org/) installed on the system
- ADT active (`/sap/bc/adt/` SICF node enabled — standard for any ADT/Eclipse usage)

## Installation

Import this repo via abapGit:

1. Open the abapGit transaction or report on your SAP system
2. Create a [new online repository](https://docs.abapgit.org/user-guide/projects/online/install.html) pointing to this GitHub repo
3. Pull and activate all objects into a transport request

## HTTP Interface

### Export a package

```
GET /sap/bc/adt/abapgit/export/packages?package={PACKAGE_NAME}&folderLogic={LOGIC}&mainLanguageOnly={BOOL}
```

**Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `package` | yes | — | ABAP package name (DEVCLASS), e.g. `Z_MY_PKG` |
| `folderLogic` | no | `PREFIX` | `PREFIX`, `FULL`, or `MIXED` |
| `mainLanguageOnly` | no | `false` | `true` or `X` to skip translations |

**Responses:**

| Status | Meaning |
|--------|---------|
| 200 | ZIP binary (Content-Type: application/zip) |
| 400 | Missing or empty `package` parameter |
| 404 | Package does not exist |
| 500 | Serialization error |

**Note:** This is a read-only GET endpoint. No CSRF token is required.

### Example with curl

```bash
# Export a single package
curl -sk -u user:pass \
  "https://host:port/sap/bc/adt/abapgit/export/packages?package=Z_MY_PKG&sap-client=100" \
  -o Z_MY_PKG.zip

# Export with options: FULL folder logic, main language only
curl -sk -u user:pass \
  "https://host:port/sap/bc/adt/abapgit/export/packages?package=Z_MY_PKG&folderLogic=FULL&mainLanguageOnly=true&sap-client=100" \
  -o Z_MY_PKG.zip
```

### What the ZIP contains

The ZIP has a standard abapGit directory structure:

```
.abapgit.xml                                ← abapGit manifest
src/
  package.devc.xml                           ← package metadata
  zcl_my_class.clas.abap                     ← class source
  zcl_my_class.clas.xml                      ← class metadata
  zcl_my_class.clas.testclasses.abap         ← unit tests (if any)
  zif_my_interface.intf.abap                 ← interface source
  zif_my_interface.intf.xml                  ← interface metadata
  z_my_report.prog.abap                     ← report source
  z_my_report.prog.xml                      ← report metadata
  ...                                        ← 100+ object types supported
```

This is the same format that abapGit uses for its "Package to ZIP" feature and for git repositories.

## Architecture

**3 objects, no SICF configuration needed:**

| Object | Type | Purpose |
|--------|------|---------|
| `ZCL_ABAPGIT_ADT_EXP_APP` | Class | Application class (extends `CL_ADT_DISC_RES_APP_BASE`), registers the `/packages` resource under `/sap/bc/adt/abapgit/export` |
| `ZCL_ABAPGIT_ADT_EXP_RES` | Class | Resource handler (extends `CL_ADT_REST_RESOURCE`), handles GET requests — validates package, calls `ZCL_ABAPGIT_ZIP=>EXPORT`, returns ZIP via `IF_REST_ENTITY` |
| `ZABAPGIT_ADT_EXPORT` | ENHO | BAdI implementations for `BADI_ADT_REST_RFC_APPLICATION` (routing) and `BADI_ADT_DISCOVERY_PROVIDER` (makes endpoint discoverable via `/sap/bc/adt/discovery`) |

The pattern is based on the [abapGit ADT_Backend](https://github.com/abapGit/ADT_Backend) repository.

## Authorizations

The calling user needs (typically already granted to any ADT developer):

| Auth Object | Activity | Notes |
|-------------|----------|-------|
| `S_ADT_RES` | — | ADT resource access for `/sap/bc/adt/abapgit/export` (checked by ADT framework automatically) |
| `S_DEVELOP` | 03 (Display) | Read access to ABAP objects being serialized (checked by abapGit's serializers per object type) |

## Companion: MCP Server

This repo provides the SAP-side endpoint to export arbitrary ABAP packages in a abapGit compatible format.
The companion [aibap.mcp](https://github.com/Hochfrequenz/aibap.mcp) provides a MCP tool (`export_package`) that calls this endpoint and allows for a workflow where you vibe code in SAP using the ADT API and then sync to git by exporting the package and commiting and pushing it from your own localhost.

This also allows for a workaround where you don't use git branches in a SAP system (where you could have only 1 active branch at a time per repo):
Code in SAP via aibap.mcp ➡️ run tests in SAP via aibap.mcp ➡️ export the package using `export_package` tool from aibap.mcp to your localhost ➡️ push to feature branch from localhost ➡️ run CI (e.g. abapLint) ➡️ merge to main ➡️ repeat.
This approach is "SAP first" instead of "git first" but has way faster roundtrip times compared to code locally ➡️ push to git ➡️ pull into SAP.

## Verified on

- **System:** S/4HANA on srvhfuhana (SAP_BASIS 756)
- **Date:** 2026-03-25
- **Test:** `GET .../packages?package=Z_ADT_MCP_TEST` returned 200 OK, valid ZIP with 15 files (classes, interfaces, function groups, test classes, `.abapgit.xml`)
