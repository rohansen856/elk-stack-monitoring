/**
 * Must match the backend's minimum (app/schemas/user.py and
 * app/schemas/password_reset.py). The UI previously enforced 8 characters on
 * reset and nothing on registration, so users hit an unexplained 422.
 */
export const MIN_PASSWORD_LENGTH = 12
