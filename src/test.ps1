# Define a ScriptConfig object with event tracking
$Script:ScriptConfig = [PSCustomObject]@{
    Name  = "DefaultName"
    Value = 42
}

# Function to set up property change detection
Function Enable-PropertyChangeTracking {
    param (
        [PSCustomObject]$Object
    )

    # Convert to PSObject for adding dynamic members
    $TrackedObject = [PSObject]$Object

    # Create a hashtable to store original values (backing fields)
    $BackingFields = @{}

    foreach ($Property in $TrackedObject.PSObject.Properties) {
        $PropertyName = $Property.Name
        $OriginalValue = $Property.Value

        # Store the original value in the backing fields
        $BackingFields[$PropertyName] = $OriginalValue

        # Remove the original property
        $TrackedObject.PSObject.Properties.Remove($PropertyName)

        # Add a script property with a custom getter and setter
        $TrackedObject | Add-Member -MemberType ScriptProperty -Name $PropertyName -Value {
            $BackingFields[$args[0]]
        }.GetNewClosure() -SecondValue {
            param($Value)
            $OldValue = $BackingFields[$args[0]]

            if ($OldValue -ne $Value) {
                $BackingFields[$args[0]] = $Value

                # Trigger an event on property change
                $this.TriggerPropertyChangeEvent.Invoke($this, @(
                    @{
                        PropertyName = $args[0]
                        OldValue     = $OldValue
                        NewValue     = $Value
                    }
                ))
            }
        }.GetNewClosure()
    }

    # Add an event handler to the object
    $TrackedObject | Add-Member -MemberType ScriptMethod -Name TriggerPropertyChangeEvent -Value {
        param (
            [object]$Sender,
            [hashtable]$EventArgs
        )
        Write-Output "Property '{0}' changed from '{1}' to '{2}'" -f $EventArgs.PropertyName, $EventArgs.OldValue, $EventArgs.NewValue
    }

    return $TrackedObject
}

# Apply tracking to ScriptConfig
$Script:ScriptConfig = Enable-PropertyChangeTracking -Object $Script:ScriptConfig

# Example: Modify properties to trigger events
$Script:ScriptConfig.Name = "UpdatedName"
$Script:ScriptConfig.Value = 99
