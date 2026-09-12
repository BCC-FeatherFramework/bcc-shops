function Notify(message, typeOrDuration, maybeDuration)
    local duration = type(typeOrDuration) == 'number' and typeOrDuration or tonumber(maybeDuration) or 4000
    return exports['feather-notify']:ShowNotification({ message = tostring(message), duration = duration, style = 'right' })
end
exports['feather-core']:RegisterRPC('bcc-shop:NotifyClient', function(data)
    Notify(data.message, data.type, data.duration)
end)
