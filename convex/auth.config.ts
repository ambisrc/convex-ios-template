import type { AuthConfig } from "convex/server";

const appleSignInClientIds = process.env.APPLE_SIGN_IN_CLIENT_IDS?.split(",")
  .map((clientId) => clientId.trim())
  .filter(Boolean);

export default {
  providers: [
    {
      domain: "https://appleid.apple.com",
      applicationID: appleSignInClientIds?.[0] ?? "com.ambimake.reflection",
    },
  ],
} satisfies AuthConfig;
