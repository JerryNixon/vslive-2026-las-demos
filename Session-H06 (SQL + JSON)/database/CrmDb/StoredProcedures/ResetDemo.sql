/*
    ResetDemo
    ─────────
    Resets CrmDb to its original seed state.
    - Restores any contacts modified during the demo (email, phone changes)
    - Safe to run multiple times.

    EXEC dbo.ResetDemo;
*/
CREATE OR ALTER PROCEDURE dbo.ResetDemo
AS
BEGIN
    SET NOCOUNT ON;

    -- Reset Contact 1 (Kirk) — demo modifies Email and Phone
    UPDATE dbo.Contact
    SET Email = 'jkirk@starfleet.org',
        Phone = '555-0001'
    WHERE ContactId = 1;

    PRINT 'CrmDb reset to initial state.';
END
GO
