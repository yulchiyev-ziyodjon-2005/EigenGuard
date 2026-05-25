# Superadmin Keys

Bu papkaga **Superadmin Ed25519 public key** joylashtiriladi — air-gapped deployment'lar
shu kalit orqali license sertifikatini offline tasdiqlaydi.

## Generatsiya (Superadmin tomonida)

```bash
# Private key (siz saqlaysiz, hech qachon tarqatmang)
openssl genpkey -algorithm Ed25519 -out superadmin_private.pem

# Public key (deployment paketiga qo'shing)
openssl pkey -in superadmin_private.pem -pubout -out superadmin_public.pem
```

## O'rnatish (deployment paketi ichida)

```
backend/keys/superadmin_public.pem    # bu yerga ko'chiring (0644 ruxsat)
```

Docker compose volume mount'i `backend/keys` ni `/app/keys` ga read-only mount qiladi.

Air-gapped deployment'da quyidagi env qo'shing:
```
DEPLOYMENT_MODE=air_gapped
LICENSE_PUBLIC_KEY_PATH=/app/keys/superadmin_public.pem
```

## Sertifikat formati

Har bir license sertifikati `payload.signature` (base64url) ko'rinishida saqlanadi.
Payload — JSON: `{license_key, tenant_id, expires_at, features, max_devices, max_users}`.
Signature — Ed25519 podpisi base64url-encoded.

License model'dagi `signed_certificate` ustunda saqlanadi.

**.gitignore:** `*.pem` fayllari hech qachon git'ga commit qilinmaydi.
