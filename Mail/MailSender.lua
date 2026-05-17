local _, Shatter = ...

local MailSender = {}
Shatter.MailSender = MailSender
Shatter.RegisterModule("MailSender", MailSender)

function MailSender:Initialize()
end

function MailSender:PrepareNext()
    if Shatter.MainFrame then
        Shatter.MainFrame:SetStatus("Return mail workflow is blocked until PrimalMailer send-flow validation is implemented.", true, 4)
    end
    if Shatter.MailSession then
        Shatter.MailSession:Log("warn", "Return mail workflow blocked pending PrimalMailer send-flow validation.")
    end
    return false
end
