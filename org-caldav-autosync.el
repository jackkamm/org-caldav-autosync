;;; org-caldav-autosync.el --- Autosync for org-caldav  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Jack Kamm

;; Author: Jack Kamm <jackkamm@gmail.com>
;; Keywords: calendar, caldav

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Companion autosync mode for org-caldav.
;; Originally based on:
;; https://www.reddit.com/r/orgmode/comments/8rl8ep/comment/e0sb5j0/?utm_source=share&utm_medium=web2x&context=3

;;; Code:

(defcustom org-caldav-autosync-idle-seconds 300
  "Idle time for `org-caldav-autosync-mode'."
  :type 'number)

(defcustom org-caldav-autosync-agenda-p t
  "Whether to check for autosync before building the agenda.
`org-caldav-autosync-agenda-seconds' controls how often the sync
occurs."
  :type 'boolean)

(defcustom org-caldav-autosync-agenda-seconds 86400
  "Time until `org-agenda' re-prompts for sync."
  :type 'number)

(defvar org-caldav-autosync-idle-timer nil
  "Timer that `org-caldav-autosync-when-idle' used to reschedule itself, or nil.")

(defvar org-caldav-autosync-last-time nil
  "The last time `org-caldav-sync' ran or was prompted to run.")

(defun org-caldav-autosync-after-save-hook ()
  (when (cl-some (lambda (x) (file-equal-p x (buffer-file-name)))
                 (org-caldav-get-org-files-for-sync))
    (org-caldav-autosync-when-idle org-caldav-autosync-idle-seconds)))

(defun org-caldav-autosync-when-idle (secs)
  "Sync with CalDav the next time Emacs is idle for SECS seconds."
  (when org-caldav-autosync-idle-timer
    (cancel-timer org-caldav-autosync-idle-timer))
  (setq org-caldav-autosync-idle-timer
	(run-with-idle-timer
	 secs nil (lambda () (let ((org-caldav-delete-org-entries 'always)
                                   (org-caldav-delete-calendar-entries 'always)
                                   (org-caldav-show-sync-results nil))
                               (org-caldav-sync))))))

(defun org-caldav-autosync-cancel-timer ()
  "Cancel the current autosync timer."
  (when org-caldav-autosync-idle-timer
    (cancel-timer org-caldav-autosync-idle-timer)
    (setq org-caldav-autosync-idle-timer nil)))

(defun org-caldav-autosync-sync-advice (&rest r)
  "Advice around org-caldav-sync to handle the autosync timers."
  (setq org-caldav-autosync-last-time (float-time))
  ;; Cancel scheduled sync, since we've just done so. Also prevents
  ;; recursively scheduling syncs due to `org-caldav-save-buffers'.
  (org-caldav-autosync-cancel-timer))

(defun org-caldav-autosync-agenda-advice (&rest r)
  "Advice around org-agenda to autosync with caldav."
  (when (and org-caldav-autosync-agenda-p
             (or (not org-caldav-autosync-last-time)
                 (> (- (float-time) org-caldav-autosync-last-time)
                    org-caldav-autosync-agenda-seconds)))
    (org-caldav-sync)))

;;;###autoload
(define-minor-mode org-caldav-autosync-mode
  "Minor mode to autosync with CalDav.

Whenever an Org file is saved, a timer will be set to sync with
the CalDav server when idle. This ensures changes in Org are
automatically propagated to iCalendar. See
`org-caldav-autosync-idle-seconds' to customize this.

Also, whenever the Agenda is built, sync with the CalDav server
if it has been a long time since the last sync. This ensures
changes in iCalendar are propagated to Org. See
`org-caldav-autosync-agenda-p' and
`org-caldav-autosync-agenda-seconds' to customize this behavior."
  :global t
  (if org-caldav-autosync-mode
      (progn
        (add-hook 'after-save-hook #'org-caldav-autosync-after-save-hook)
        (advice-add #'org-caldav-sync :after #'org-caldav-autosync-sync-advice)
        (advice-add #'org-agenda :before #'org-caldav-autosync-agenda-advice))
    (remove-hook 'after-save-hook #'org-caldav-autosync-after-save-hook)
    (advice-remove #'org-caldav-sync #'org-caldav-autosync-sync-advice)
    (advice-remove #'org-agenda #'org-caldav-autosync-agenda-advice)
    (org-caldav-autosync-cancel-timer)))

(provide 'org-caldav-autosync)
;;; org-caldav-autosync.el ends here
