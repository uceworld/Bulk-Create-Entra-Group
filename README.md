# 📘 Entra ID Bulk Group Creation  
## Operator / Admin Production Run Guide

---

## 1. Purpose of the Script

This PowerShell script bulk-creates **Entra ID security groups** from a CSV file using **Microsoft Graph PowerShell (MgGraph)**.

It supports:
- ✅ Assigned groups
- ✅ Dynamic user groups
- ✅ Dynamic device groups
- ✅ Role-assignable groups (with enforcement)
- ✅ Safe duplicate detection
- ✅ Detailed validation and failure reporting

The script is **idempotent by name**:  
it will **never overwrite or modify existing groups**.

---

## 2. Prerequisites (Do Not Skip)

### 2.1 Required Permissions

The account running the script **must** have:

| Permission | Type | Required |
|-----------|------|----------|
| `Group.ReadWrite.All` | Application or Delegated | ✅ |
| `Directory.Read.All` | Delegated | ✅ |
| **Privileged Role Admin** | Azure AD role | ⚠️ Required for role‑assignable groups |

> ⚠️ If role‑assignable groups are in scope, the operator **must** be a **Privileged Role Administrator**.

---

### 2.2 Required Modules

Install Microsoft Graph PowerShell (once per machine):

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Verify availability:

```powershell
Get-Module Microsoft.Graph -ListAvailable
```

---

### 2.3 Authentication

Before running the script, authenticate explicitly:

```powershell
Connect-MgGraph -Scopes Group.ReadWrite.All,Directory.Read.All
```

Verify context:

```powershell
Get-MgContext
```

Ensure:
- ✅ Tenant ID is correct  
- ✅ Account is expected admin  
- ✅ Scopes include `Group.ReadWrite.All`

---

## 3. CSV File Requirements

### 3.1 Required Columns

Your CSV **must** contain the following headers (case‑insensitive):

```
DisplayName,MailNickname,Description,RoleAssignable,MembershipType,MembershipRule
```

---

### 3.2 Column Rules

| Column | Required | Notes |
|--------|----------|-------|
| `DisplayName` | ✅ | Must be unique in tenant |
| `MailNickname` | ✅ | Must be unique |
| `Description` | ❌ | Optional |
| `RoleAssignable` | ❌ | `Yes` or `No` |
| `MembershipType` | ❌ | `Assigned`, `DynamicUser`, `DynamicDevice` |
| `MembershipRule` | ⚠️ | **Required** for dynamic groups |

---

### 3.3 Valid Examples

```csv
DisplayName,MailNickname,Description,RoleAssignable,MembershipType,MembershipRule
HR-Admins,hr-admins,HR admin access,Yes,Assigned,
Finance-Users,finance-users,Finance users group,No,DynamicUser,"(user.department -eq ""Finance"")"
Corp-Devices,corp-devices,Corporate devices,No,DynamicDevice,"(device.deviceOwnership -eq ""Company"")"
```

---

### 3.4 Common CSV Errors (Script Will Catch These)

| Issue | Result |
|-------|--------|
| Empty `DisplayName` | ❌ Fail |
| Empty `MailNickname` | ❌ Fail |
| Dynamic group without rule | ❌ Fail |
| Duplicate `DisplayName` | ⚠️ Skipped |
| `RoleAssignable` + Dynamic | ⚠️ Forced to `Assigned` |

---

## 4. Pre-Production Safety Checklist

Before running in production, **always** do the following:

### ✅ 4.1 Dry-Run in a Test Tenant
- Use a dev / sandbox Entra tenant  
- Run with a small CSV sample  
- Confirm output matches expectations  

### ✅ 4.2 Validate CSV Before Execution

Run this quick validation:

```powershell
Import-Csv .\groups.csv | Format-Table
```

Check for:
- Blank rows  
- Typos in `MembershipType`  
- Missing quotes in `MembershipRule`  

### ✅ 4.3 Confirm No Unintended Names

The script blocks duplicates, but you should still confirm intent:

```powershell
Import-Csv .\groups.csv | Select DisplayName
```

---

## 5. Running the Script (Production)

### 5.1 File Placement

Ensure both files are in the **same directory**:

```
creategroups.ps1
groups.csv
```

### 5.2 Execution

From PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then:

```powershell
./creategroups.ps1
```

---

## 6. Understanding Terminal Output

### 6.1 Real-Time Logs

| Prefix | Meaning |
|--------|---------|
| `[INFO]` | Processing step |
| `[OK]` | Group created |
| `[WARN]` | Rule enforcement or skip |
| `[FAIL]` | Group not created |

Example:

```
[WARN] Role-assignable group cannot be dynamic. MembershipType forced to 'Assigned'.
```

---

### 6.2 Execution Summary

At the end you will see:

```
========== EXECUTION SUMMARY ==========
Total groups processed : 14
Groups created         : 10
Skipped (name exists)  : 1
Failed                 : 3
```

---

### 6.3 Failure Breakdown

Failures are categorized automatically:

```
Failure breakdown:
 - Dynamic membership missing rule : 1
 - Missing required fields : 2
```

---

### 6.4 Failed Row Details (Critical for Debugging)

```
Failed row details:
Row DisplayName     Reason                         Columns
--- -----------     ------                         -------
8   Corp-Devices2  Dynamic membership missing rule MembershipRule
11  ucbot          Missing required fields         DisplayName, MailNickname
```

This maps directly back to the CSV file, making fixes trivial.

---

## 7. Post-Run Validation

### 7.1 Spot-Check Groups

```powershell
Get-MgGroup -Filter "startswith(displayName,'HR-')"
```

### 7.2 Validate Dynamic Membership

```powershell
Get-MgGroup -Filter "displayName eq 'Finance-Users'" | 
    Select DisplayName, MembershipRule
```

### 7.3 Confirm Role-Assignable Groups

```powershell
Get-MgGroup -Filter "isAssignableToRole eq true"
```

---

## 8. Operational Best Practices

✅ Run during change windows  
✅ Keep CSVs in source control  
✅ Require peer review for dynamic rules  
❌ Never run blindly with unreviewed CSVs  
❌ Never use Global Admin when unnecessary  

---

## 9. Rollback Strategy (Important)

The script **does not delete groups**.

If rollback is required:
- Manually delete created groups  
- Or restore from backup / Entra recycle bin  

Group IDs are printed in logs for traceability.

---

## 10. Final Operator Confidence Statement

If you follow this guide:
- ✅ You will **not** overwrite existing groups  
- ✅ You will **not** create invalid objects  
- ✅ You will know **exactly** what failed and why  
- ✅ You can safely run this at **enterprise scale**  

**This is production-ready automation.**
