///|
#cfg(target="native")
const DB_ENABLE_WAL : String = "PRAGMA journal_mode=WAL"

///|
#cfg(target="native")
const DB_ENABLE_FOREIGN_KEYS : String = "PRAGMA foreign_keys=ON"

///|
#cfg(target="native")
const DB_SET_BUSY_TIMEOUT : String = "PRAGMA busy_timeout=5000"

///|
const DB_CREATE_METADATA : String =
  #|CREATE TABLE IF NOT EXISTS metadata (
  #|  name TEXT PRIMARY KEY,
  #|  value TEXT NOT NULL
  #|)

///|
const DB_CREATE_SESSIONS : String =
  #|CREATE TABLE IF NOT EXISTS sessions (
  #|  id TEXT PRIMARY KEY,
  #|  csrf TEXT NOT NULL,
  #|  expires INTEGER NOT NULL,
  #|  epoch INTEGER NOT NULL DEFAULT 0,
  #|  user_id TEXT NOT NULL DEFAULT '',
  #|  login TEXT NOT NULL DEFAULT '',
  #|  tokens TEXT NOT NULL DEFAULT '',
  #|  access_expires INTEGER NOT NULL DEFAULT 0,
  #|  refresh_expires INTEGER NOT NULL DEFAULT 0
  #|)

///|
const DB_CREATE_AUTHORIZATIONS : String =
  #|CREATE TABLE IF NOT EXISTS authorizations (
  #|  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  #|  id TEXT NOT NULL,
  #|  target_id TEXT NOT NULL,
  #|  epoch INTEGER NOT NULL,
  #|  phase TEXT NOT NULL,
  #|  credentials TEXT NOT NULL DEFAULT '',
  #|  user_code TEXT NOT NULL DEFAULT '',
  #|  verification_uri TEXT NOT NULL DEFAULT '',
  #|  expires INTEGER NOT NULL,
  #|  next_poll INTEGER NOT NULL DEFAULT 0,
  #|  interval INTEGER NOT NULL DEFAULT 5,
  #|  backoff INTEGER NOT NULL DEFAULT 0,
  #|  token_issued INTEGER NOT NULL DEFAULT 0,
  #|  message TEXT NOT NULL DEFAULT '',
  #|  PRIMARY KEY (session_id, id)
  #|)

///|
const DB_CREATE_ONE_ACTIVE_DEVICE_INDEX : String =
  #|CREATE UNIQUE INDEX IF NOT EXISTS one_active_device ON authorizations(session_id)
  #|WHERE phase IN ('starting', 'pending', 'verifying')

///|
// Preserve the foreign-key contract even when the host does not let us
// enable foreign_keys. These triggers also apply to databases created by Native.
const DB_CREATE_AUTHORIZATION_SESSION_INSERT_TRIGGER : String =
  #|CREATE TRIGGER IF NOT EXISTS authorizations_require_session_insert
  #|BEFORE INSERT ON authorizations
  #|WHEN NOT EXISTS (SELECT 1 FROM sessions WHERE id=NEW.session_id)
  #|BEGIN
  #|  SELECT RAISE(ABORT, 'authorization session is missing');
  #|END

///|
const DB_CREATE_AUTHORIZATION_SESSION_UPDATE_TRIGGER : String =
  #|CREATE TRIGGER IF NOT EXISTS authorizations_require_session_update
  #|BEFORE UPDATE OF session_id ON authorizations
  #|WHEN NOT EXISTS (SELECT 1 FROM sessions WHERE id=NEW.session_id)
  #|BEGIN
  #|  SELECT RAISE(ABORT, 'authorization session is missing');
  #|END

///|
const DB_CREATE_SESSION_AUTHORIZATION_PARENT_TRIGGER : String =
  #|CREATE TRIGGER IF NOT EXISTS sessions_preserve_authorization_parent
  #|BEFORE UPDATE OF id ON sessions
  #|WHEN NEW.id IS NOT OLD.id
  #|  AND EXISTS (SELECT 1 FROM authorizations WHERE session_id=OLD.id)
  #|BEGIN
  #|  SELECT RAISE(ABORT, 'session has a pending authorization');
  #|END

///|
const DB_CREATE_SESSION_DELETE_AUTHORIZATIONS_TRIGGER : String =
  #|CREATE TRIGGER IF NOT EXISTS sessions_delete_authorizations
  #|AFTER DELETE ON sessions
  #|BEGIN
  #|  DELETE FROM authorizations WHERE session_id=OLD.id;
  #|END

///|
const DB_BEGIN_IMMEDIATE : String = "BEGIN IMMEDIATE"

///|
const DB_COMMIT : String = "COMMIT"

///|
const DB_ROLLBACK : String = "ROLLBACK"

///|
const QUERY_KEY_CHECK : String = "SELECT value FROM metadata WHERE name='key-check-v1'"

///|
const DB_INSERT_KEY_CHECK : String = "INSERT INTO metadata VALUES ('key-check-v1', ?)"

///|
const QUERY_SESSION : String =
  #|SELECT csrf, expires, epoch, user_id, login, tokens, access_expires, refresh_expires
  #|FROM sessions
  #|WHERE id=? AND expires>?

///|
const DB_DELETE_EXPIRED_SESSIONS : String = "DELETE FROM sessions WHERE expires<=?"

///|
const DB_DELETE_EXPIRED_AUTHORIZATIONS : String = "DELETE FROM authorizations WHERE expires<=?"

///|
const DB_INSERT_SESSION : String = "INSERT INTO sessions (id,csrf,expires) VALUES (?,?,?)"

///|
const DB_DELETE_SESSION : String = "DELETE FROM sessions WHERE id=?"

///|
const DB_INSTALL_SESSION_TOKENS : String =
  #|UPDATE sessions
  #|SET user_id=?, login=?, tokens=?, access_expires=?, refresh_expires=?, epoch=epoch+?
  #|WHERE id=? AND epoch=? AND expires>?

///|
const DB_EXPIRE_SESSION_AUTH : String =
  #|UPDATE sessions SET tokens='', epoch=epoch+1
  #|WHERE id=? AND epoch=?

///|
const DB_INCREMENT_SESSION_EPOCH : String = "UPDATE sessions SET epoch=epoch+1 WHERE id=?"

///|
const DB_INCREMENT_CURRENT_SESSION_EPOCH : String =
  #|UPDATE sessions SET epoch=epoch+1
  #|WHERE id=? AND epoch=?

///|
const QUERY_AUTHORIZATION : String =
  #|SELECT target_id, epoch, phase, credentials, user_code, verification_uri,
  #|       expires, next_poll, interval, backoff, token_issued, message
  #|FROM authorizations
  #|WHERE session_id=? AND id=?

///|
const QUERY_VISIBLE_AUTHORIZATION : String =
  #|SELECT id FROM authorizations
  #|WHERE session_id=? AND phase != 'alias'
  #|ORDER BY (phase IN ('starting', 'pending', 'verifying')) DESC, epoch DESC, rowid DESC
  #|LIMIT 1

///|
const DB_INSERT_AUTHORIZATION_ALIAS : String =
  #|INSERT INTO authorizations (session_id, id, target_id, epoch, phase, expires)
  #|VALUES (?, ?, ?, ?, 'alias', ?)

///|
const DB_INSERT_STARTING_AUTHORIZATION : String =
  #|INSERT INTO authorizations (session_id, id, target_id, epoch, phase, expires)
  #|VALUES (?, ?, ?, ?, 'starting', ?)

///|
const DB_INSERT_CANCELLED_AUTHORIZATION : String =
  #|INSERT INTO authorizations (session_id, id, target_id, epoch, phase, expires)
  #|VALUES (?, ?, ?, ?, 'cancelled', ?)

///|
const DB_END_AUTHORIZATION : String =
  #|UPDATE authorizations SET phase=?, credentials='', message=?
  #|WHERE session_id=? AND id=? AND phase IN ('starting', 'pending', 'verifying')

///|
const DB_COMPLETE_AUTHORIZATION : String =
  #|UPDATE authorizations SET phase='completed', credentials='', message=''
  #|WHERE session_id=? AND id=?

///|
const DB_SAVE_AUTHORIZATION : String =
  #|UPDATE authorizations
  #|SET phase=?, credentials=?, user_code=?, verification_uri=?, expires=?,
  #|    next_poll=?, interval=?, backoff=?, token_issued=?, message=?
  #|WHERE session_id=? AND id=?
